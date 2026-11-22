-- Keep a mistaken empty draft removable while protecting its sections and any
-- published content from a direct API DELETE.
create or replace function public.enforce_empty_draft_course_delete()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.is_published or exists (
    select 1 from public.course_sections s where s.course_id = old.id
  ) then
    raise exception using errcode = '23514',
      message = 'Only an unpublished course without sections can be deleted.';
  end if;
  return old;
end;
$function$;

revoke all on function public.enforce_empty_draft_course_delete() from public, anon, authenticated;

create trigger courses_delete_only_empty_drafts
before delete on public.courses
for each row execute function public.enforce_empty_draft_course_delete();
