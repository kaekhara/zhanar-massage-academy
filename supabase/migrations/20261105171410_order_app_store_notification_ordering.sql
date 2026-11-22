-- Keep App Store Server Notification V2 state monotonic per transaction.
-- Apple retries notifications and may deliver transaction events out of order.
alter table public.verified_purchases
  add column last_notification_signed_at timestamptz,
  add column last_notification_uuid text;
