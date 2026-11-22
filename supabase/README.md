# ZHANAR Massage backend

The Supabase project is configured for the iOS app. `migrations/` mirrors the migrations applied to the live project. `schema.sql` records the current full schema and RLS policies; `seed.sql` contains the two draft courses and their lesson outlines. The seeded courses remain unpublished until real content is added.

## Before launch

See [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) for account delivery, App Store, video upload, and end-to-end verification steps. Use [`COURSE_IMPORT.md`](COURSE_IMPORT.md) to prepare and import a course package; the included example manifest shows the expected format.

Admins can upload course covers and individual lesson videos from the iOS editor. JWT-protected `create-admin-cover-upload` and `create-admin-video-upload` functions check the current admin role and issue scoped upload tokens. Covers go to the public artwork bucket; videos stream to the private bucket in 6 MiB chunks. Use `scripts/import_course.py` for larger files or complete course-package uploads.

The course importer uploads media first, then calls the `service_role`-only `import_course_bundle` RPC. Course rows and the publish flag are changed in one database transaction, so a failed catalog update cannot leave a partially updated course visible. Unreferenced uploaded files remain private and can be reused on retry.

- Configure production SMTP in Supabase Auth before public email signup when email confirmation is enabled. Supabase's built-in mail service is limited to project team addresses and is not intended for production.
- Phone OTP remains an optional login method; configure a production SMS provider in Supabase Auth before enabling it for learners.
- Create a non-consumable App Store product for every published course, using the exact `store_product_id` value from the `courses` row. The current draft IDs are `com.zhanar.course.standard` and `com.zhanar.course.selfmassage`; `Massage app.xcodeproj/ZhanarProducts.storekit` is only for local StoreKit testing.
- Add the lesson titles, descriptions, and real video assets. Lesson screens stream a private-bucket video when its `video_path` is set and the signed-in user has a verified purchase.
- Set the Supabase function secret `APPLE_APP_ID` (the numeric Apple app ID from App Store Connect) before enabling production transactions. The `verify-storekit-purchase` Edge Function verifies StoreKit JWS transactions and writes only verified, account-bound purchases; client entitlements alone cannot unlock protected videos.
- Set `https://ocbmqllnugshdqtylzpu.supabase.co/functions/v1/app-store-notifications` as the App Store Server Notifications V2 production and sandbox URL in App Store Connect. It verifies Apple-signed notifications and revokes or restores access on refunds/reversals. Production requires the `APPLE_APP_ID` function secret.
- Publish a course only after its real content and purchase flow are ready.
- Lesson progress can be created or updated only by the owning signed-in user when the lesson belongs to a course with an active, verified purchase. Read and delete access remain scoped to the user's own progress.
- `lesson_resume_state` stores last playback positions per user and lesson. RLS limits rows to their owner and limits inserts/updates to lessons in an active purchased course or published preview lessons. It cascades on account deletion and is synced with an on-device copy when connectivity returns.
- `is_published` controls whether a course appears for new learners and can receive new purchases. Existing owners retain access to its course structure, referenced private videos, and progress while their verified purchase is active and those files remain in Storage; detached purchases remain reclaimable after account deletion.

The iOS target builds with Xcode and Supabase Swift 2.55.6. The Supabase URL and publishable key are configured in `Massage app/AuthManager.swift`. The publishable key is intended for client use; access is restricted by database RLS policies and server-side purchase verification. Never put a Supabase secret or service-role key in the iOS app.
- Account deletion is available from the profile screen. The authenticated `delete-account` Edge Function deletes the Auth user and cascades profile/progress data. Verified purchase rows are detached from that user so the signed-in Apple purchaser can reclaim a non-consumable with a verified StoreKit transaction after creating another account.
