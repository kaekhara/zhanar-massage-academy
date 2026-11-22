-- Restrict course assets to the formats supported by the lesson player and importer.
update storage.buckets
set allowed_mime_types = array['video/mp4', 'video/quicktime', 'video/x-m4v']::text[]
where id = 'course-videos';
