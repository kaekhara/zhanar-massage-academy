-- Keep the verified App Store transaction after deleting a learning account.
-- The next signed-in Apple purchaser can reclaim the transaction only by
-- presenting Apple's verified current entitlement to the verification function.
alter table public.verified_purchases
  alter column user_id drop not null;

alter table public.verified_purchases
  drop constraint verified_purchases_user_id_fkey;

alter table public.verified_purchases
  add constraint verified_purchases_user_id_fkey
  foreign key (user_id) references auth.users (id) on delete set null;
