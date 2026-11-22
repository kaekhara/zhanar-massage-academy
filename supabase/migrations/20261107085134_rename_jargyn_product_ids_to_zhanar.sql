-- Rename unpublished draft course, section, and lesson IDs before App Store products are created.
-- This migration intentionally refuses to run after publication, purchase, progress, resume,
-- cover, or video data exists, because those records must keep stable identifiers.
do $$
declare
  old_course_count integer;
begin
  select count(*) into old_course_count
  from public.courses
  where id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
    and store_product_id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage');

  if old_course_count <> 2 then
    raise exception 'Expected exactly two unpublished Jargyn draft courses before renaming; found %', old_course_count;
  end if;

  if exists (
    select 1 from public.courses
    where id like 'com.zhanar.course.%' or store_product_id like 'com.zhanar.course.%'
  ) then
    raise exception 'A ZHANAR course identifier already exists; refusing to merge catalog entries';
  end if;

  if exists (
    select 1 from public.courses
    where id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
      and (is_published or cover_path is not null)
  ) then
    raise exception 'A Jargyn course is published or has a cover; preserve its current identifiers';
  end if;

  if exists (
    select 1
    from public.verified_purchases p
    where p.product_id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
  ) then
    raise exception 'Purchases already reference a Jargyn product; preserve its StoreKit identifier';
  end if;

  if exists (
    select 1
    from public.lessons l
    join public.course_sections s on s.id = l.section_id
    join public.courses c on c.id = s.course_id
    where c.id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
      and l.video_path is not null
  ) then
    raise exception 'A Jargyn course has video content; preserve its storage paths and identifiers';
  end if;

  if exists (
    select 1
    from public.lesson_progress p
    join public.lessons l on l.id = p.lesson_id
    join public.course_sections s on s.id = l.section_id
    where s.course_id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
  ) or exists (
    select 1
    from public.lesson_resume_state r
    join public.lessons l on l.id = r.lesson_id
    join public.course_sections s on s.id = l.section_id
    where s.course_id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage')
  ) then
    raise exception 'Learner progress exists for a Jargyn course; preserve stable lesson identifiers';
  end if;
end
$$;

-- Enable key updates to cascade through the course graph and purchase product reference.
alter table public.course_sections drop constraint course_sections_course_id_fkey;
alter table public.lessons drop constraint lessons_section_id_fkey;
alter table public.verified_purchases drop constraint verified_purchases_product_id_fkey;

alter table public.course_sections
  add constraint course_sections_course_id_fkey
  foreign key (course_id) references public.courses (id) on update cascade on delete cascade;
alter table public.lessons
  add constraint lessons_section_id_fkey
  foreign key (section_id) references public.course_sections (id) on update cascade on delete cascade;
alter table public.verified_purchases
  add constraint verified_purchases_product_id_fkey
  foreign key (product_id) references public.courses (store_product_id) on update cascade;

-- Update parent identifiers after the cascade constraints are in place.
update public.courses
set id = replace(id, 'com.jargyn', 'com.zhanar'),
    store_product_id = replace(store_product_id, 'com.jargyn', 'com.zhanar')
where id in ('com.jargyn.course.standard', 'com.jargyn.course.selfmassage');

update public.course_sections
set id = replace(id, 'com.jargyn', 'com.zhanar')
where id like 'com.jargyn.course.%';

update public.lessons
set id = replace(id, 'com.jargyn', 'com.zhanar')
where id like 'com.jargyn.course.%';
