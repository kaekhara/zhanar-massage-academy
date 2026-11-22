drop policy if exists "Course videos require an active verified purchase" on storage.objects;
drop policy if exists "Course videos require an active purchase or published preview" on storage.objects;

create policy "Course videos require an active purchase or published preview"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'course-videos'
    and (
      exists (
        select 1
        from public.verified_purchases p
        where p.user_id = (select auth.uid())
          and p.product_id = split_part(storage.objects.name, '/', 1)
          and p.revoked_at is null
      )
      or exists (
        select 1
        from public.lessons l
        join public.course_sections s on s.id = l.section_id
        join public.courses c on c.id = s.course_id
        where l.video_path = storage.objects.name
          and l.is_preview
          and c.is_published
          and split_part(l.video_path, '/', 1) = c.store_product_id
      )
    )
  );
