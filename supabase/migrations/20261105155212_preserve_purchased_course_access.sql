drop policy if exists "Published courses are readable" on public.courses;
grant select on public.verified_purchases to anon;
create policy "Published or purchased courses are readable"
  on public.courses for select to anon, authenticated
  using (
    is_published
    or (
      (select auth.uid()) is not null
      and exists (
        select 1
        from public.verified_purchases p
        where p.user_id = (select auth.uid())
          and p.product_id = courses.store_product_id
          and p.revoked_at is null
      )
    )
  );

drop policy if exists "Sections in published courses are readable" on public.course_sections;
create policy "Published or purchased course sections are readable"
  on public.course_sections for select to anon, authenticated
  using (
    exists (
      select 1
      from public.courses c
      where c.id = course_sections.course_id
        and (
          c.is_published
          or exists (
            select 1
            from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

drop policy if exists "Lessons in published courses are readable" on public.lessons;
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
            select 1
            from public.verified_purchases p
            where p.user_id = (select auth.uid())
              and p.product_id = c.store_product_id
              and p.revoked_at is null
          )
        )
    )
  );

drop policy if exists "Users can create progress for purchased course lessons" on public.lesson_progress;
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

drop policy if exists "Users can update progress for purchased course lessons" on public.lesson_progress;
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
