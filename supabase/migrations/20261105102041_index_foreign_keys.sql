create index lesson_progress_lesson_idx on public.lesson_progress (lesson_id);

create index verified_purchases_user_product_idx
  on public.verified_purchases (user_id, product_id)
  where revoked_at is null;

create index verified_purchases_product_idx on public.verified_purchases (product_id);
