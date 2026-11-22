-- These SECURITY DEFINER functions are internal trigger entry points. They
-- must not be directly callable through Supabase RPC.
revoke all on function public.enforce_published_course_ready() from public, anon, authenticated;
revoke all on function public.enforce_course_video_storage_integrity() from public, anon, authenticated;
