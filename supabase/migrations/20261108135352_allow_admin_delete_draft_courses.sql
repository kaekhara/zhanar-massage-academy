-- An administrator may remove a mistaken draft course. Published courses stay
-- protected; the verified_purchases foreign key also prevents deletion of a
-- course with any recorded App Store transaction.
revoke delete on public.courses from anon;
grant delete on public.courses to authenticated;

create policy "Course admins can delete draft courses"
  on public.courses for delete to authenticated
  using (
    not is_published
    and exists (
      select 1 from public.course_admins a
      where a.user_id = (select auth.uid())
    )
  );
