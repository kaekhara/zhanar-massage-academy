drop policy if exists "Users can create their own lesson progress" on public.lesson_progress;
drop policy if exists "Users can update their own lesson progress" on public.lesson_progress;

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
        and c.is_published
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
        and c.is_published
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
        and c.is_published
        and exists (
          select 1
          from public.verified_purchases p
          where p.user_id = (select auth.uid())
            and p.product_id = c.store_product_id
            and p.revoked_at is null
        )
    )
  );
