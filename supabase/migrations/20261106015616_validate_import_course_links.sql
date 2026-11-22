-- Strengthen the atomic importer: lesson section references must belong to the same package, and video paths must stay in the course namespace.
-- Apply the catalog rows for one imported course in a single transaction.
-- Video objects are uploaded first; if any catalog write or publish check fails,
-- PostgreSQL rolls back the course, section, and lesson changes together.
create or replace function public.import_course_bundle(
  p_course jsonb,
  p_sections jsonb,
  p_lessons jsonb,
  p_publish boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_course_id text;
  v_product_id text;
  v_existing_product_id text;
begin
  if p_course is null or jsonb_typeof(p_course) <> 'object' then
    raise exception using errcode = '22023', message = 'p_course must be a JSON object';
  end if;
  if p_sections is null or jsonb_typeof(p_sections) <> 'array' or jsonb_array_length(p_sections) = 0 then
    raise exception using errcode = '22023', message = 'p_sections must be a non-empty JSON array';
  end if;
  if p_lessons is null or jsonb_typeof(p_lessons) <> 'array' or jsonb_array_length(p_lessons) = 0 then
    raise exception using errcode = '22023', message = 'p_lessons must be a non-empty JSON array';
  end if;
  if p_publish is null then
    raise exception using errcode = '22023', message = 'p_publish cannot be null';
  end if;

  select incoming.id, incoming.store_product_id
    into v_course_id, v_product_id
  from jsonb_to_record(p_course) as incoming(id text, store_product_id text);

  if nullif(btrim(v_course_id), '') is null
     or nullif(btrim(v_product_id), '') is null
     or nullif(btrim(p_course ->> 'title'), '') is null then
    raise exception using errcode = '22023', message = 'course id, store_product_id, and title are required';
  end if;

  select c.store_product_id
    into v_existing_product_id
  from public.courses as c
  where c.id = v_course_id;

  if found and v_existing_product_id <> v_product_id then
    raise exception using errcode = '23514', message = 'store_product_id cannot change for an existing course';
  end if;

  if exists (
    select 1
    from public.courses as c
    where c.store_product_id = v_product_id
      and c.id <> v_course_id
  ) then
    raise exception using errcode = '23505', message = 'store_product_id already belongs to a different course';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_sections) as incoming(id text, title text, sort_order integer)
    where incoming.id is null
       or nullif(btrim(incoming.id), '') is null
       or incoming.title is null
       or nullif(btrim(incoming.title), '') is null
       or incoming.sort_order is null
       or incoming.sort_order < 1
  ) then
    raise exception using errcode = '22023', message = 'every section requires an id, title, and positive sort_order';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_sections) as incoming(id text, sort_order integer)
    join public.course_sections as existing on existing.id = incoming.id
    where existing.course_id <> v_course_id
       or existing.sort_order <> incoming.sort_order
  ) then
    raise exception using errcode = '23514', message = 'existing section ownership and order cannot change';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_lessons) as incoming(
      id text,
      section_id text,
      title text,
      video_path text,
      sort_order integer
    )
    where incoming.id is null
       or nullif(btrim(incoming.id), '') is null
       or incoming.section_id is null
       or nullif(btrim(incoming.section_id), '') is null
       or incoming.title is null
       or nullif(btrim(incoming.title), '') is null
       or incoming.video_path is null
       or nullif(btrim(incoming.video_path), '') is null
       or incoming.sort_order is null
       or incoming.sort_order < 1
  ) then
    raise exception using errcode = '22023', message = 'every lesson requires an id, section_id, title, video_path, and positive sort_order';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_lessons) as incoming(id text, section_id text, video_path text)
    left join jsonb_to_recordset(p_sections) as supplied_section(id text)
      on supplied_section.id = incoming.section_id
    where supplied_section.id is null
       or left(incoming.video_path, length(v_product_id) + 1) <> (v_product_id || '/')
  ) then
    raise exception using errcode = '23503', message = 'every lesson must reference a section in this course package and use this course product ID as its video folder';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_lessons) as incoming(id text, section_id text, sort_order integer)
    join public.lessons as existing on existing.id = incoming.id
    where existing.section_id <> incoming.section_id
       or existing.sort_order <> incoming.sort_order
       or not exists (
         select 1
         from public.course_sections as old_section
         where old_section.id = existing.section_id
           and old_section.course_id = v_course_id
       )
  ) then
    raise exception using errcode = '23514', message = 'existing lesson ownership, section, and order cannot change';
  end if;

  insert into public.courses as existing_course (
    id,
    store_product_id,
    title,
    subtitle,
    description,
    cover_path,
    sort_order,
    is_published
  )
  select
    incoming.id,
    incoming.store_product_id,
    incoming.title,
    coalesce(incoming.subtitle, ''),
    coalesce(incoming.description, ''),
    incoming.cover_path,
    incoming.sort_order,
    false
  from jsonb_to_record(p_course) as incoming(
    id text,
    store_product_id text,
    title text,
    subtitle text,
    description text,
    cover_path text,
    sort_order integer
  )
  on conflict (id) do update set
    store_product_id = excluded.store_product_id,
    title = excluded.title,
    subtitle = excluded.subtitle,
    description = excluded.description,
    cover_path = coalesce(excluded.cover_path, existing_course.cover_path),
    sort_order = excluded.sort_order,
    is_published = false;

  insert into public.course_sections as existing_section (id, course_id, title, description, sort_order)
  select incoming.id, v_course_id, incoming.title, coalesce(incoming.description, ''), incoming.sort_order
  from jsonb_to_recordset(p_sections) as incoming(
    id text,
    title text,
    description text,
    sort_order integer
  )
  on conflict (id) do update set
    title = excluded.title,
    description = excluded.description,
    sort_order = excluded.sort_order;

  insert into public.lessons as existing_lesson (
    id,
    section_id,
    title,
    description,
    video_path,
    duration_seconds,
    sort_order,
    is_preview
  )
  select
    incoming.id,
    incoming.section_id,
    incoming.title,
    coalesce(incoming.description, ''),
    incoming.video_path,
    incoming.duration_seconds,
    incoming.sort_order,
    coalesce(incoming.is_preview, false)
  from jsonb_to_recordset(p_lessons) as incoming(
    id text,
    section_id text,
    title text,
    description text,
    video_path text,
    duration_seconds integer,
    sort_order integer,
    is_preview boolean
  )
  on conflict (id) do update set
    title = excluded.title,
    description = excluded.description,
    video_path = excluded.video_path,
    duration_seconds = excluded.duration_seconds,
    is_preview = excluded.is_preview;

  if p_publish then
    update public.courses as c
    set is_published = true
    where c.id = v_course_id;
  end if;

  return jsonb_build_object(
    'course_id', v_course_id,
    'is_published', p_publish,
    'sections_applied', jsonb_array_length(p_sections),
    'lessons_applied', jsonb_array_length(p_lessons)
  );
end;
$function$;

revoke all on function public.import_course_bundle(jsonb, jsonb, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.import_course_bundle(jsonb, jsonb, jsonb, boolean) to service_role;
