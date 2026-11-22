create table public.lesson_resume_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  lesson_id text not null references public.lessons (id) on delete cascade,
  position_seconds double precision not null check (position_seconds >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

alter table public.lesson_resume_state enable row level security;
revoke all on public.lesson_resume_state from anon, authenticated;
grant select, insert, update, delete on public.lesson_resume_state to authenticated;

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

create index lesson_resume_state_updated_at_idx
  on public.lesson_resume_state (user_id, updated_at desc);
