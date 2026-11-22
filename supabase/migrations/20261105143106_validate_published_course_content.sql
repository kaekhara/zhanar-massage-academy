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
