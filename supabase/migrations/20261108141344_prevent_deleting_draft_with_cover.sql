-- A cover is a separate Storage object. Keep the draft until its cover can be
-- removed through the Storage API, avoiding an orphaned public file.
create or replace function public.enforce_empty_draft_course_delete()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.is_published or old.cover_path is not null or exists (
    select 1 from public.course_sections s where s.course_id = old.id
  ) then
    raise exception using errcode = '23514',
      message = 'Only an unpublished course without sections or a cover can be deleted.';
  end if;
  return old;
end;
$function$;
