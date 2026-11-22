-- Course editor role. Rows are provisioned by a trusted database operator only.
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

grant select, insert, update on public.courses to authenticated;
grant select, insert, update, delete on public.course_sections to authenticated;
grant select, insert, update, delete on public.lessons to authenticated;

create policy "Course admins can read all courses"
  on public.courses for select to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can create courses"
  on public.courses for insert to authenticated
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can update courses"
  on public.courses for update to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));

create policy "Course admins can read all sections"
  on public.course_sections for select to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can create sections"
  on public.course_sections for insert to authenticated
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can update sections"
  on public.course_sections for update to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can delete sections"
  on public.course_sections for delete to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));

create policy "Course admins can read all lessons"
  on public.lessons for select to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can create lessons"
  on public.lessons for insert to authenticated
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can update lessons"
  on public.lessons for update to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));
create policy "Course admins can delete lessons"
  on public.lessons for delete to authenticated
  using (exists (
    select 1 from public.course_admins a where a.user_id = (select auth.uid())
  ));

