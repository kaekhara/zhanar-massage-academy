-- Draft catalog entries based on the supplied screenshots.
-- Courses stay unpublished until the real lesson text and video files are added.
-- Seed is additive: rerunning it must never overwrite a real catalog or unpublish a course.
insert into public.courses (
  id, store_product_id, title, subtitle, description, sort_order, is_published
)
values
  (
    'com.zhanar.course.standard',
    'com.zhanar.course.standard',
    'Классикалық массаж курсы',
    '24 сабақ · 9 бөлім',
    'ZHANAR массаж мектебінен массаж бойынша оқу курсы.',
    1,
    false
  ),
  (
    'com.zhanar.course.selfmassage',
    'com.zhanar.course.selfmassage',
    'Өзіне-өзі массаж',
    '30 сабақ · 7 бөлім',
    'ZHANAR массаж мектебінен өзіне-өзі массаж жасау курсы.',
    2,
    false
  )
on conflict (id) do nothing;

with section_seed (course_id, section_key, title, sort_order, lesson_count) as (
  values
    ('com.zhanar.course.standard', 'anatomy', 'Анатомия', 1, 3),
    ('com.zhanar.course.standard', 'diagnostics', 'Диагностика жасау', 2, 3),
    ('com.zhanar.course.standard', 'therapeutic', 'Емдік массаж', 3, 4),
    ('com.zhanar.course.standard', 'cupping', 'Банка қою', 4, 2),
    ('com.zhanar.course.standard', 'fire', 'От массаж', 5, 3),
    ('com.zhanar.course.standard', 'vacuum', 'Вакуум массаж', 6, 2),
    ('com.zhanar.course.standard', 'lymphatic', 'Лимфодренажный массаж', 7, 3),
    ('com.zhanar.course.standard', 'honey', 'Бал массаж', 8, 2),
    ('com.zhanar.course.standard', 'conclusion', 'Қорытынды', 9, 2),
    ('com.zhanar.course.selfmassage', 'preparation', 'Массажға дайындық', 1, 3),
    ('com.zhanar.course.selfmassage', 'face', 'Бет массажы', 2, 5),
    ('com.zhanar.course.selfmassage', 'neck_shoulders', 'Мойын және иық', 3, 4),
    ('com.zhanar.course.selfmassage', 'hands', 'Қол массажы', 4, 4),
    ('com.zhanar.course.selfmassage', 'legs', 'Аяқ массажы', 5, 5),
    ('com.zhanar.course.selfmassage', 'aftercare', 'Қайталау және күтім', 6, 4),
    ('com.zhanar.course.selfmassage', 'conclusion', 'Қорытынды', 7, 5)
), section_rows as (
  insert into public.course_sections (id, course_id, title, description, sort_order)
  select
    course_id || '.' || section_key,
    course_id,
    title,
    '',
    sort_order
  from section_seed
  on conflict (id) do nothing
  returning id
)
insert into public.lessons (id, section_id, title, description, sort_order, is_preview)
select
  section_seed.course_id || '.' || section_seed.section_key || '.' || lpad(lesson_number::text, 2, '0'),
  section_seed.course_id || '.' || section_seed.section_key,
  lesson_number || '-сабақ',
  'Сабақ материалы мектептен алынған бейнемен толықтырылады.',
  lesson_number,
  false
from section_seed
cross join lateral generate_series(1, section_seed.lesson_count) as lesson_number
on conflict (id) do nothing;
