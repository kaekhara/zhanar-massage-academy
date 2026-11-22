import { HttpError } from './upstream.mjs';

const courseFields = [
  'id', 'store_product_id', 'is_published', 'sort_order', 'title', 'title_ru', 'subtitle', 'subtitle_ru',
  'description', 'description_ru', 'category', 'category_ru', 'instructor_name', 'instructor_title',
  'instructor_title_ru', 'instructor_bio', 'instructor_bio_ru', 'cover_path',
].join(',');
const lessonFields = 'id,title,title_ru,description,description_ru,is_preview,sort_order,duration_seconds';
const sectionFields = 'id,title,title_ru,description,description_ru,sort_order';

function fail(status, message) {
  throw new HttpError(status, message);
}

function ensureLogin(user) {
  if (!user?.id || !user?.accessToken) fail(401, 'sign_in_required');
}

function ensureMethod(actual, ...allowed) {
  if (!allowed.includes(actual)) fail(405, 'method_not_allowed');
}

function routeID(value) {
  try { return validID(decodeURIComponent(value)); }
  catch { fail(400, 'invalid_id'); }
}

function validID(value) {
  if (typeof value !== 'string' || !value.trim() || value.length > 1024 || /[\u0000-\u001f\u007f]/u.test(value)) {
    fail(400, 'invalid_id');
  }
  return value;
}

function objectPath(value) {
  if (typeof value !== 'string' || /[\\\u0000-\u001f\u007f]/u.test(value)) return null;
  const parts = value.split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) return null;
  return parts.map(encodeURIComponent).join('/');
}

function storageBase(base) {
  if (!base) fail(503, 'storage_unavailable');
  return new URL('/storage/v1/', base).href;
}

function endpoint(table, params) {
  return '/rest/v1/' + table + '?' + new URLSearchParams(params);
}

// Keep list reads within PostgREST's default row limit while including older progress and purchases.
async function allRows(read, table, params) {
  const result = [];
  const limit = 200;
  for (let offset = 0; ; offset += limit) {
    const page = await read(endpoint(table, { ...params, offset, limit }));
    result.push(...page);
    if (page.length < limit) return result;
  }
}

function sorted(rows) {
  return [...(rows || [])].sort((a, b) => a.sort_order - b.sort_order || a.id.localeCompare(b.id));
}

function courseData(row, base, details, editor = false) {
  const sections = row.course_sections || [];
  const lessons = sections.flatMap(section => section.lessons || []);
  const cover = objectPath(row.cover_path);
  const model = {
    id: row.id, productID: row.store_product_id, owned: Boolean(row.verified_purchases?.length),
    title: row.title, titleRu: row.title_ru, subtitle: row.subtitle, subtitleRu: row.subtitle_ru,
    description: row.description, descriptionRu: row.description_ru,
    category: row.category, categoryRu: row.category_ru, instructorName: row.instructor_name,
    instructorTitle: row.instructor_title, instructorTitleRu: row.instructor_title_ru,
    instructorBio: row.instructor_bio, instructorBioRu: row.instructor_bio_ru,
    coverURL: cover ? storageBase(base) + 'object/public/course-covers/' + cover : null,
    lessonCount: lessons.length,
    durationSeconds: lessons.reduce((total, lesson) => total + (lesson.duration_seconds || 0), 0),
  };
  if (details) {
    model.sections = sorted(sections).map(section => ({
      id: section.id, title: section.title, titleRu: section.title_ru,
      description: section.description, descriptionRu: section.description_ru,
      ...(editor ? { sortOrder: section.sort_order } : {}),
      lessons: sorted(section.lessons).map(lesson => ({
        id: lesson.id, title: lesson.title, titleRu: lesson.title_ru,
        description: lesson.description, descriptionRu: lesson.description_ru,
        isPreview: lesson.is_preview, durationSeconds: lesson.duration_seconds,
        ...(editor ? { sortOrder: lesson.sort_order, videoPath: lesson.video_path } : {}),
      })),
    }));
  }
  if (editor) Object.assign(model, { sortOrder: row.sort_order, isPublished: row.is_published, coverPath: row.cover_path });
  return model;
}

async function courses(read, user, base, { library = false, id = undefined } = {}) {
  const tree = id
    ? 'course_sections(' + sectionFields + ',lessons(' + lessonFields + '))'
    : 'course_sections(lessons(duration_seconds))';
  const params = { select: courseFields + ',' + tree, order: 'sort_order.asc,id.asc' };
  if (user) {
    // An embedded left join preserves unowned catalog entries, the inner join selects only the library.
    params.select += library ? ',verified_purchases!inner(product_id)' : ',verified_purchases(product_id)';
    params['verified_purchases.user_id'] = 'eq.' + user.id;
    params['verified_purchases.revoked_at'] = 'is.null';
  }
  if (id) {
    const rows = await read(endpoint('courses', { ...params, id: 'eq.' + id, limit: 1 }));
    const course = rows[0];
    if (!course || (!course.is_published && !course.verified_purchases?.length)) fail(404, 'course_not_found');
    return { course: courseData(course, base, true) };
  }
  if (!library) params.is_published = 'eq.true';
  const rows = await allRows(read, 'courses', params);
  return { courses: rows.map(row => courseData(row, base, false)) };
}

async function lessonAccess(read, user, lessonID, previewAllowed) {
  const params = {
    select: 'id,is_preview,video_path,course_sections(courses(store_product_id,is_published,verified_purchases(product_id)))',
    id: 'eq.' + lessonID,
    'course_sections.courses.verified_purchases.user_id': 'eq.' + user.id,
    'course_sections.courses.verified_purchases.revoked_at': 'is.null', limit: 1,
  };
  const [lesson] = await read(endpoint('lessons', params));
  const course = lesson?.course_sections?.courses;
  if (!course) fail(404, 'lesson_not_found');
  const owned = Boolean(course.verified_purchases?.length);
  if (!course.is_published && !owned) fail(404, 'lesson_not_found');
  if (!owned && !(previewAllowed && lesson.is_preview)) fail(403, 'course_access_required');
  return { lesson, course };
}

async function video(read, user, base, id) {
  const { lesson, course } = await lessonAccess(read, user, id, true);
  const path = objectPath(lesson.video_path);
  if (!path || lesson.video_path.split('/')[0] !== course.store_product_id) fail(404, 'video_unavailable');
  const result = await read('/storage/v1/object/sign/course-videos/' + path, {
    method: 'POST', body: { expiresIn: 3600 },
  });
  const signed = result?.signedURL;
  if (typeof signed !== 'string' || !signed.startsWith('/object/sign/course-videos/')) {
    fail(502, 'invalid_video_link');
  }
  return { url: new URL(signed.slice(1), storageBase(base)).href };
}

function upsert(read, table, conflict, row, ignoreDuplicates = false) {
  const resolution = ignoreDuplicates ? 'ignore-duplicates' : 'merge-duplicates';
  return read(endpoint(table, { on_conflict: conflict }), {
    method: 'POST', body: row, headers: { Prefer: 'resolution=' + resolution + ',return=minimal' },
  });
}

async function progress(method, read, user, body) {
  ensureMethod(method, 'GET', 'POST');
  if (method === 'GET') {
    const rows = await allRows(read, 'lesson_progress', {
      select: 'lesson_id', user_id: 'eq.' + user.id, order: 'lesson_id.asc',
    });
    return { completedLessonIDs: rows.map(row => row.lesson_id) };
  }
  const lessonID = validID(body?.lessonID);
  await lessonAccess(read, user, lessonID, false);
  await upsert(read, 'lesson_progress', 'user_id,lesson_id', { user_id: user.id, lesson_id: lessonID }, true);
  return { lessonID, completed: true };
}

async function resume(method, read, user, body) {
  ensureMethod(method, 'GET', 'POST');
  if (method === 'GET') {
    const rows = await allRows(read, 'lesson_resume_state', {
      select: 'lesson_id,position_seconds,updated_at', user_id: 'eq.' + user.id, order: 'updated_at.desc,lesson_id.asc',
    });
    return { positions: rows.map(row => ({
      lessonID: row.lesson_id, positionSeconds: row.position_seconds, updatedAt: row.updated_at,
    })) };
  }
  const lessonID = validID(body?.lessonID);
  if (!Number.isFinite(body.positionSeconds) || body.positionSeconds < 0) fail(400, 'invalid_playback_position');
  const now = Date.now();
  const stamp = body.updatedAt === undefined ? now : Date.parse(body.updatedAt);
  if (!Number.isFinite(stamp) || stamp <= 0) fail(400, 'invalid_playback_timestamp');
  await lessonAccess(read, user, lessonID, true);
  await upsert(read, 'lesson_resume_state', 'user_id,lesson_id', {
    user_id: user.id, lesson_id: lessonID, position_seconds: body.positionSeconds,
    updated_at: new Date(Math.min(now, stamp)).toISOString(),
  });
  return { saved: true };
}

async function profile(method, read, user, body) {
  ensureMethod(method, 'GET', 'PATCH');
  if (method === 'GET') {
    const [row] = await read(endpoint('profiles', { select: 'display_name', id: 'eq.' + user.id, limit: 1 }));
    return { displayName: row?.display_name ?? user.displayName ?? '' };
  }
  if (typeof body?.displayName !== 'string') fail(400, 'invalid_display_name');
  const displayName = body.displayName.trim();
  if (!displayName || [...displayName].length > 100 || /[\u0000-\u001f\u007f]/u.test(displayName)) {
    fail(400, 'invalid_display_name');
  }
  await upsert(read, 'profiles', 'id', { id: user.id, display_name: displayName, updated_at: new Date().toISOString() });
  return { displayName };
}

export async function academy({ method, path, body, user, request, supabaseURL = process.env.SUPABASE_URL }) {
  const read = (url, options = {}) => request(url, { method: 'GET', ...options, token: user?.accessToken });
  const matchCourse = /^\/api\/courses\/([^/]+)$/u.exec(path);
  if (path === '/api/courses' || matchCourse) {
    ensureMethod(method, 'GET');
    return courses(read, user, supabaseURL, { id: matchCourse && routeID(matchCourse[1]) });
  }
  if (path === '/api/library') {
    ensureMethod(method, 'GET');
    ensureLogin(user);
    return courses(read, user, supabaseURL, { library: true });
  }
  const matchVideo = /^\/api\/lessons\/([^/]+)\/video$/u.exec(path);
  if (matchVideo) {
    ensureMethod(method, 'GET');
    ensureLogin(user);
    return video(read, user, supabaseURL, routeID(matchVideo[1]));
  }
  if (path === '/api/progress' || path === '/api/resume' || path === '/api/profile') {
    ensureLogin(user);
    if (path === '/api/progress') return progress(method, read, user, body);
    if (path === '/api/resume') return resume(method, read, user, body);
    return profile(method, read, user, body);
  }
  fail(404, 'not_found');
}

export { allRows, courseData, courseFields, sectionFields, lessonFields, endpoint, ensureLogin, ensureMethod, fail, routeID, validID };
