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
  cover_path text,
  sort_order integer not null default 0,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.course_sections (
  id text primary key,
  course_id text not null references public.courses (id) on delete cascade,
  title text not null,
  description text not null default '',
  sort_order integer not null default 0,
  unique (course_id, sort_order)
);

create table public.lessons (
  id text primary key,
  section_id text not null references public.course_sections (id) on delete cascade,
  title text not null,
  description text not null default '',
  video_path text,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  sort_order integer not null default 0,
  is_preview boolean not null default false,
  unique (section_id, sort_order)
);

create table public.verified_purchases (
  transaction_id text primary key,
  original_transaction_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null references public.courses (store_product_id),
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


alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_sections enable row level security;
alter table public.lessons enable row level security;
alter table public.verified_purchases enable row level security;
alter table public.lesson_progress enable row level security;

grant select, insert, update on public.profiles to authenticated;
grant select on public.courses, public.course_sections, public.lessons to anon, authenticated;
grant select on public.verified_purchases to authenticated;
grant select, insert, update, delete on public.lesson_progress to authenticated;

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

create policy "Published courses are readable"
  on public.courses for select to anon, authenticated
  using (is_published);

create policy "Sections in published courses are readable"
  on public.course_sections for select to anon, authenticated
  using (exists (
    select 1 from public.courses c
    where c.id = course_sections.course_id and c.is_published
  ));

create policy "Lessons in published courses are readable"
  on public.lessons for select to anon, authenticated
  using (exists (
    select 1
    from public.course_sections s
    join public.courses c on c.id = s.course_id
    where s.id = lessons.section_id and c.is_published
  ));

create policy "Users can read their verified purchases"
  on public.verified_purchases for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can read their own lesson progress"
  on public.lesson_progress for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own lesson progress"
  on public.lesson_progress for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own lesson progress"
  on public.lesson_progress for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own lesson progress"
  on public.lesson_progress for delete to authenticated
  using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('course-videos', 'course-videos', false)
on conflict (id) do update set public = false;

create policy "Course videos require an active verified purchase"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'course-videos'
    and exists (
      select 1 from public.verified_purchases p
      where p.user_id = (select auth.uid())
        and p.product_id = split_part(storage.objects.name, '/', 1)
        and p.revoked_at is null
    )
  );
