create function public.prevent_stale_lesson_resume_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.updated_at <= old.updated_at then
    return null;
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_stale_lesson_resume_update() from public, anon, authenticated;

create trigger lesson_resume_state_prevent_stale_update
before update on public.lesson_resume_state
for each row
execute function public.prevent_stale_lesson_resume_update();
