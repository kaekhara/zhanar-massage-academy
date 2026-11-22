-- Keep drafts editable, but never expose partly untranslated course content.
-- The existing deferred triggers call this function after the complete
-- course/section/lesson transaction, including the atomic package import.
create or replace function public.assert_published_course_ready(p_course_id text)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.courses c
    where c.id = p_course_id and c.is_published
  ) then
    return;
  end if;

  if exists (
    select 1 from public.courses c
    where c.id = p_course_id
      and (
        nullif(btrim(c.title), '') is null
        or nullif(btrim(c.store_product_id), '') is null
      )
  ) then
    raise exception using errcode = '23514',
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
    select 1 from public.course_sections s
    where s.course_id = p_course_id
  ) then
    raise exception using errcode = '23514',
      message = 'A published course must have at least one section.';
  end if;

  if exists (
    select 1 from public.course_sections s
    where s.course_id = p_course_id
      and (
        nullif(btrim(s.title), '') is null
        or not exists (select 1 from public.lessons l where l.section_id = s.id)
      )
  ) then
    raise exception using errcode = '23514',
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
          select 1 from storage.objects o
          where o.bucket_id = 'course-videos' and o.name = l.video_path
        )
      )
  ) then
    raise exception using errcode = '23514',
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
