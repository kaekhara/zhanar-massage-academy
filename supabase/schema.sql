-- ZHANAR Massage learning backend. Keep this schema synchronized with the
-- `jargyn_learning_core` migration applied to the Supabase project.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id text primary key,
  store_product_id text not null unique,
  title text not null,
  subtitle text not null default '',
  description text not null default '',
  title_ru text,
  subtitle_ru text,
  description_ru text,
  category text,
  category_ru text,
  instructor_name text,
  instructor_title text,
  instructor_title_ru text,
  instructor_bio text,
  instructor_bio_ru text,
  cover_path text,
  sort_order integer not null default 0,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.course_sections (
  id text primary key,
  course_id text not null references public.courses (id) on update cascade on delete cascade,
  title text not null,
  description text not null default '',
  title_ru text,
  description_ru text,
  sort_order integer not null default 0,
  unique (course_id, sort_order)
);

create table public.lessons (
  id text primary key,
  section_id text not null references public.course_sections (id) on update cascade on delete cascade,
  title text not null,
  description text not null default '',
  title_ru text,
  description_ru text,
  video_path text,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  sort_order integer not null default 0,
  is_preview boolean not null default false,
  unique (section_id, sort_order)
);

create table public.verified_purchases (
  transaction_id text primary key,
  original_transaction_id text not null,
  user_id uuid references auth.users (id) on delete set null,
  product_id text not null references public.courses (store_product_id) on update cascade,
  purchased_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.lesson_progress (
  user_id uuid not null references auth.users (id) on delete cascade,
  lesson_id text not null references public.lessons (id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table public.lesson_resume_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  lesson_id text not null references public.lessons (id) on delete cascade,
  position_seconds double precision not null check (position_seconds >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create function public.prevent_stale_lesson_resume_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.updated_at <= old.updated_at then
    return null;
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_stale_lesson_resume_update() from public, anon, authenticated;

create trigger lesson_resume_state_prevent_stale_update
before update on public.lesson_resume_state
for each row
execute function public.prevent_stale_lesson_resume_update();

create index lesson_progress_lesson_idx on public.lesson_progress (lesson_id);
create index lesson_resume_state_updated_at_idx on public.lesson_resume_state (user_id, updated_at desc);
create index lesson_resume_state_lesson_id_idx on public.lesson_resume_state (lesson_id);
create index verified_purchases_user_product_idx on public.verified_purchases (user_id, product_id) where revoked_at is null;
create index verified_purchases_product_idx on public.verified_purchases (product_id);

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_sections enable row level security;
alter table public.lessons enable row level security;
alter table public.verified_purchases enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.lesson_resume_state enable row level security;

grant select, insert, update on public.profiles to authenticated;
grant select on public.courses, public.course_sections, public.lessons to anon, authenticated;
grant select on public.verified_purchases to authenticated;
grant select on public.verified_purchases to anon;
grant select, insert, update, delete on public.lesson_progress to authenticated;
revoke all on public.lesson_resume_state from anon, authenticated;
grant select, insert, update, delete on public.lesson_resume_state to authenticated;

create table public.course_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.course_admins enable row level security;
revoke all on public.course_admins from anon, authenticated;
grant select on public.course_admins to authenticated;
create policy "Course admins can read their own role"
  on public.course_admins for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Users can create their own profile"
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "Published or purchased courses are readable"
  on public.courses for select to anon, authenticated
  using (
    is_published
    or (
      (select auth.uid()) is not null
      and exists (
        select 1 from public.verified_purchases p
        where p.user_id = (select auth.uid())
          and p.product_id = courses.store_product_id
          and p.revoked_at is null
      )
    )
  );

create policy "Published or purchased course sections are readable"
  on public.course_sections for select to anon, authenticated
  using (
    exists (
      select 1 from public.courses c
      where c.id = course_sections.course_id
        and (
          c.is_published
          or exists (
            select 1 from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

create policy "Published or purchased course lessons are readable"
  on public.lessons for select to anon, authenticated
  using (
    exists (
      select 1
      from public.course_sections s
      join public.courses c on c.id = s.course_id
      where s.id = lessons.section_id
        and (
          c.is_published
          or exists (
            select 1 from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

create policy "Users can read their verified purchases"
  on public.verified_purchases for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their own lesson progress"
  on public.lesson_progress for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their own lesson resume state"
  on public.lesson_resume_state for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create resume state for accessible lessons"
  on public.lesson_resume_state for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_resume_state.lesson_id
        and (
          (l.is_preview and c.is_published)
          or exists (
            select 1 from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

create policy "Users can update resume state for accessible lessons"
  on public.lesson_resume_state for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_resume_state.lesson_id
        and (
          (l.is_preview and c.is_published)
          or exists (
            select 1 from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_resume_state.lesson_id
        and (
          (l.is_preview and c.is_published)
          or exists (
            select 1 from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

create policy "Users can delete their own lesson resume state"
  on public.lesson_resume_state for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create progress for purchased course lessons"
  on public.lesson_progress for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_progress.lesson_id
        and exists (
          select 1
          from public.verified_purchases p
          where p.user_id = (select auth.uid())
            and p.product_id = c.store_product_id
            and p.revoked_at is null
        )
    )
  );

create policy "Users can update progress for purchased course lessons"
  on public.lesson_progress for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_progress.lesson_id
        and exists (
          select 1
          from public.verified_purchases p
          where p.user_id = (select auth.uid())
            and p.product_id = c.store_product_id
            and p.revoked_at is null
        )
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.lessons l
      join public.course_sections s on s.id = l.section_id
      join public.courses c on c.id = s.course_id
      where l.id = lesson_progress.lesson_id
        and exists (
          select 1
          from public.verified_purchases p
          where p.user_id = (select auth.uid())
            and p.product_id = c.store_product_id
            and p.revoked_at is null
        )
    )
  );

create policy "Users can delete their own lesson progress"
  on public.lesson_progress for delete to authenticated
  using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public, allowed_mime_types)
values ('course-videos', 'course-videos', false, array['video/mp4', 'video/quicktime', 'video/x-m4v']::text[])
on conflict (id) do update
  set public = false,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "Course videos require an active purchase or published preview"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'course-videos'
    and (
      exists (
        select 1 from public.verified_purchases p
        where p.user_id = (select auth.uid())
          and p.product_id = split_part(storage.objects.name, '/', 1)
          and p.revoked_at is null
      )
      or exists (
        select 1
        from public.lessons l
        join public.course_sections s on s.id = l.section_id
        join public.courses c on c.id = s.course_id
        where l.video_path = storage.objects.name
          and l.is_preview
          and c.is_published
          and split_part(l.video_path, '/', 1) = c.store_product_id
      )
    )
  );
-- Published courses must be complete and every lesson video must exist in the
-- private course-videos bucket. Deferred triggers allow a complete course to
-- be published or edited in a single transaction.

create or replace function public.assert_published_course_ready(p_course_id text)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if not exists (
    select 1
    from public.courses c
    where c.id = p_course_id
      and c.is_published
  ) then
    return;
  end if;

  if exists (
    select 1
    from public.courses c
    where c.id = p_course_id
      and (
        nullif(btrim(c.title), '') is null
        or nullif(btrim(c.store_product_id), '') is null
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'A published course must have a title and an App Store product ID.';
  end if;

  if exists (
    select 1 from public.courses c
    where c.id = p_course_id
      and (
        nullif(btrim(c.subtitle), '') is null
        or nullif(btrim(c.description), '') is null
        or nullif(btrim(c.title_ru), '') is null
        or nullif(btrim(c.subtitle_ru), '') is null
        or nullif(btrim(c.description_ru), '') is null
        or (nullif(btrim(c.category), '') is not null and nullif(btrim(c.category_ru), '') is null)
        or (nullif(btrim(c.instructor_title), '') is not null and nullif(btrim(c.instructor_title_ru), '') is null)
        or (nullif(btrim(c.instructor_bio), '') is not null and nullif(btrim(c.instructor_bio_ru), '') is null)
      )
  ) then
    raise exception using errcode = '23514',
      message = 'A published course needs Kazakh and Russian copy for its title, subtitle, description, category, and instructor details when present.';
  end if;

  if not exists (
    select 1
    from public.course_sections s
    where s.course_id = p_course_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'A published course must have at least one section.';
  end if;

  if exists (
    select 1
    from public.course_sections s
    where s.course_id = p_course_id
      and (
        nullif(btrim(s.title), '') is null
        or not exists (
          select 1
          from public.lessons l
          where l.section_id = s.id
        )
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every section in a published course must have a title and at least one lesson.';
  end if;

  if exists (
    select 1 from public.course_sections s
    where s.course_id = p_course_id
      and (
        nullif(btrim(s.title_ru), '') is null
        or (nullif(btrim(s.description), '') is not null and nullif(btrim(s.description_ru), '') is null)
      )
  ) then
    raise exception using errcode = '23514',
      message = 'Every published section needs a Russian title and a Russian description when the Kazakh description is present.';
  end if;

  if exists (
    select 1
    from public.lessons l
    join public.course_sections s on s.id = l.section_id
    join public.courses c on c.id = s.course_id
    where s.course_id = p_course_id
      and (
        nullif(btrim(l.title), '') is null
        or nullif(btrim(l.video_path), '') is null
        or split_part(l.video_path, '/', 1) <> c.store_product_id
        or not exists (
          select 1
          from storage.objects o
          where o.bucket_id = 'course-videos'
            and o.name = l.video_path
        )
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every lesson in a published course must have a title and an uploaded video in the private course-videos bucket.';
  end if;

  if exists (
    select 1
    from public.lessons l
    join public.course_sections s on s.id = l.section_id
    where s.course_id = p_course_id
      and (
        nullif(btrim(l.title_ru), '') is null
        or (nullif(btrim(l.description), '') is not null and nullif(btrim(l.description_ru), '') is null)
      )
  ) then
    raise exception using errcode = '23514',
      message = 'Every published lesson needs a Russian title and a Russian description when the Kazakh description is present.';
  end if;
end;
$function$;

revoke all on function public.assert_published_course_ready(text) from public, anon, authenticated;

create or replace function public.enforce_published_course_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id text;
begin
  if tg_table_schema = 'public' and tg_table_name = 'courses' then
    if tg_op <> 'DELETE' then
      perform public.assert_published_course_ready(new.id);
    end if;
    if tg_op = 'UPDATE' and old.id is distinct from new.id then
      perform public.assert_published_course_ready(old.id);
    end if;
  elsif tg_table_schema = 'public' and tg_table_name = 'course_sections' then
    if tg_op = 'INSERT' then
      perform public.assert_published_course_ready(new.course_id);
    elsif tg_op = 'DELETE' then
      perform public.assert_published_course_ready(old.course_id);
    else
      perform public.assert_published_course_ready(old.course_id);
      if old.course_id is distinct from new.course_id then
        perform public.assert_published_course_ready(new.course_id);
      end if;
    end if;
  elsif tg_table_schema = 'public' and tg_table_name = 'lessons' then
    if tg_op = 'INSERT' then
      select s.course_id into v_course_id
      from public.course_sections s
      where s.id = new.section_id;
      if found then
        perform public.assert_published_course_ready(v_course_id);
      end if;
    elsif tg_op = 'DELETE' then
      select s.course_id into v_course_id
      from public.course_sections s
      where s.id = old.section_id;
      if found then
        perform public.assert_published_course_ready(v_course_id);
      end if;
    else
      select s.course_id into v_course_id
      from public.course_sections s
      where s.id = old.section_id;
      if found then
        perform public.assert_published_course_ready(v_course_id);
      end if;
      if old.section_id is distinct from new.section_id then
        select s.course_id into v_course_id
        from public.course_sections s
        where s.id = new.section_id;
        if found then
          perform public.assert_published_course_ready(v_course_id);
        end if;
      end if;
    end if;
  end if;

  return null;
end;
$function$;

create constraint trigger courses_require_complete_content
after insert or update or delete on public.courses
deferrable initially deferred
for each row execute function public.enforce_published_course_ready();

create constraint trigger sections_require_complete_content
after insert or update or delete on public.course_sections
deferrable initially deferred
for each row execute function public.enforce_published_course_ready();

create constraint trigger lessons_require_complete_content
after insert or update or delete on public.lessons
deferrable initially deferred
for each row execute function public.enforce_published_course_ready();

create or replace function public.enforce_course_video_storage_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id text;
begin
  if tg_op = 'UPDATE' then
    if old.bucket_id is not distinct from new.bucket_id
       and old.name is not distinct from new.name then
      return null;
    end if;
  end if;

  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    if old.bucket_id = 'course-videos' then
      for v_course_id in
        select distinct s.course_id
        from public.lessons l
        join public.course_sections s on s.id = l.section_id
        where l.video_path = old.name
      loop
        perform public.assert_published_course_ready(v_course_id);
      end loop;
    end if;
  end if;

  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.bucket_id = 'course-videos' then
      for v_course_id in
        select distinct s.course_id
        from public.lessons l
        join public.course_sections s on s.id = l.section_id
        where l.video_path = new.name
      loop
        perform public.assert_published_course_ready(v_course_id);
      end loop;
    end if;
  end if;

  return null;
end;
$function$;

create constraint trigger course_video_objects_remain_available
after update or delete on storage.objects
deferrable initially deferred
for each row execute function public.enforce_course_video_storage_integrity();

create or replace function public.keep_course_video_bucket_private()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id = 'course-videos' and new.public then
    raise exception using
      errcode = '23514',
      message = 'The course-videos bucket must remain private.';
  end if;
  return new;
end;
$function$;

create trigger course_video_bucket_stays_private
before insert or update of id, public on storage.buckets
for each row execute function public.keep_course_video_bucket_private();
-- These SECURITY DEFINER functions are internal trigger entry points. They
-- must not be directly callable through Supabase RPC.
revoke all on function public.enforce_published_course_ready() from public, anon, authenticated;
revoke all on function public.enforce_course_video_storage_integrity() from public, anon, authenticated;
-- Lock an existing course during import and require explicit publication when replacing published content.
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
  v_was_published boolean;
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

  select c.store_product_id, c.is_published
    into v_existing_product_id, v_was_published
  from public.courses as c
  where c.id = v_course_id
  for update;

  if found and v_existing_product_id <> v_product_id then
    raise exception using errcode = '23514', message = 'store_product_id cannot change for an existing course';
  end if;
  if found and v_was_published and not p_publish then
    raise exception using errcode = '23514', message = 'updating a published course requires explicit publication';
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
    title_ru,
    subtitle_ru,
    description_ru,
    category,
    category_ru,
    instructor_name,
    instructor_title,
    instructor_title_ru,
    instructor_bio,
    instructor_bio_ru,
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
    incoming.title_ru,
    incoming.subtitle_ru,
    incoming.description_ru,
    incoming.category,
    incoming.category_ru,
    incoming.instructor_name,
    incoming.instructor_title,
    incoming.instructor_title_ru,
    incoming.instructor_bio,
    incoming.instructor_bio_ru,
    incoming.cover_path,
    incoming.sort_order,
    false
  from jsonb_to_record(p_course) as incoming(
    id text,
    store_product_id text,
    title text,
    subtitle text,
    description text,
    title_ru text,
    subtitle_ru text,
    description_ru text,
    category text,
    category_ru text,
    instructor_name text,
    instructor_title text,
    instructor_title_ru text,
    instructor_bio text,
    instructor_bio_ru text,
    cover_path text,
    sort_order integer
  )
  on conflict (id) do update set
    store_product_id = excluded.store_product_id,
    title = excluded.title,
    subtitle = excluded.subtitle,
    description = excluded.description,
    title_ru = coalesce(excluded.title_ru, existing_course.title_ru),
    subtitle_ru = coalesce(excluded.subtitle_ru, existing_course.subtitle_ru),
    description_ru = coalesce(excluded.description_ru, existing_course.description_ru),
    category = coalesce(excluded.category, existing_course.category),
    category_ru = coalesce(excluded.category_ru, existing_course.category_ru),
    instructor_name = coalesce(excluded.instructor_name, existing_course.instructor_name),
    instructor_title = coalesce(excluded.instructor_title, existing_course.instructor_title),
    instructor_title_ru = coalesce(excluded.instructor_title_ru, existing_course.instructor_title_ru),
    instructor_bio = coalesce(excluded.instructor_bio, existing_course.instructor_bio),
    instructor_bio_ru = coalesce(excluded.instructor_bio_ru, existing_course.instructor_bio_ru),
    cover_path = coalesce(excluded.cover_path, existing_course.cover_path),
    sort_order = excluded.sort_order,
    is_published = false;

  insert into public.course_sections as existing_section (id, course_id, title, description, title_ru, description_ru, sort_order)
  select incoming.id, v_course_id, incoming.title, coalesce(incoming.description, ''), incoming.title_ru, incoming.description_ru, incoming.sort_order
  from jsonb_to_recordset(p_sections) as incoming(
    id text,
    title text,
    description text,
    title_ru text,
    description_ru text,
    sort_order integer
  )
  on conflict (id) do update set
    title = excluded.title,
    description = excluded.description,
    title_ru = coalesce(excluded.title_ru, existing_section.title_ru),
    description_ru = coalesce(excluded.description_ru, existing_section.description_ru),
    sort_order = excluded.sort_order;

  insert into public.lessons as existing_lesson (
    id,
    section_id,
    title,
    description,
    title_ru,
    description_ru,
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
    incoming.title_ru,
    incoming.description_ru,
    incoming.video_path,
    incoming.duration_seconds,
    incoming.sort_order,
    coalesce(incoming.is_preview, false)
  from jsonb_to_recordset(p_lessons) as incoming(
    id text,
    section_id text,
    title text,
    description text,
    title_ru text,
    description_ru text,
    video_path text,
    duration_seconds integer,
    sort_order integer,
    is_preview boolean
  )
  on conflict (id) do update set
    title = excluded.title,
    description = excluded.description,
    title_ru = coalesce(excluded.title_ru, existing_lesson.title_ru),
    description_ru = coalesce(excluded.description_ru, existing_lesson.description_ru),
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

-- Course editor role (mirrors 20261106150000_course_admin_mode.sql).
revoke delete on public.courses from anon;
grant select, insert, update, delete on public.courses to authenticated;
grant select, insert, update, delete on public.course_sections to authenticated;
grant select, insert, update, delete on public.lessons to authenticated;
create policy "Course admins can read all courses" on public.courses for select to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can create courses" on public.courses for insert to authenticated
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can update courses" on public.courses for update to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can delete draft courses" on public.courses for delete to authenticated
  using (not is_published and exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create or replace function public.enforce_empty_draft_course_delete()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.is_published or old.cover_path is not null or exists (
    select 1 from public.course_sections s where s.course_id = old.id
  ) then
    raise exception using errcode = '23514',
      message = 'Only an unpublished course without sections or a cover can be deleted.';
  end if;
  return old;
end;
$function$;
revoke all on function public.enforce_empty_draft_course_delete() from public, anon, authenticated;
create trigger courses_delete_only_empty_drafts
before delete on public.courses
for each row execute function public.enforce_empty_draft_course_delete();
create policy "Course admins can read all sections" on public.course_sections for select to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can create sections" on public.course_sections for insert to authenticated
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can update sections" on public.course_sections for update to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can delete sections" on public.course_sections for delete to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can read all lessons" on public.lessons for select to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can create lessons" on public.lessons for insert to authenticated
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can update lessons" on public.lessons for update to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
create policy "Course admins can delete lessons" on public.lessons for delete to authenticated
  using (exists (select 1 from public.course_admins a where a.user_id = (select auth.uid())));
