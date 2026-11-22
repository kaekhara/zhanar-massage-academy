import { randomUUID } from 'node:crypto';
import {
  allRows, courseData, courseFields, sectionFields, lessonFields, endpoint, ensureLogin, ensureMethod,
  fail, routeID, validID,
} from './academy.mjs';

const productPattern = /^[a-zA-Z0-9][a-zA-Z0-9._-]{2,99}$/;
const textFields = {
  title: 'title', titleRu: 'title_ru', subtitle: 'subtitle', subtitleRu: 'subtitle_ru',
  description: 'description', descriptionRu: 'description_ru', category: 'category', categoryRu: 'category_ru',
  instructorName: 'instructor_name', instructorTitle: 'instructor_title', instructorTitleRu: 'instructor_title_ru',
  instructorBio: 'instructor_bio', instructorBioRu: 'instructor_bio_ru',
};
const common = ['title', 'titleRu', 'description', 'descriptionRu', 'sortOrder'];
const fields = {
  courses: [...Object.keys(textFields), 'sortOrder'],
  course_sections: common,
  lessons: [...common, 'isPreview', 'durationSeconds'],
};
const assets = {
  cover: {
    idField: 'courseID', bucket: 'course-covers', table: 'courses', column: 'cover_path', maxSize: 5_000_000,
    mime: { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' },
  },
  video: {
    idField: 'lessonID', bucket: 'course-videos', table: 'lessons', column: 'video_path', maxSize: 50_000_000,
    mime: { mp4: 'video/mp4', mov: 'video/quicktime', m4v: 'video/x-m4v' },
  },
};

function checkKeys(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)
    || Object.keys(body).some(key => !allowed.includes(key))) fail(400, 'invalid_admin_fields');
}
function integer(value, name) {
  if (!Number.isInteger(value) || value < 0 || value > 2147483647) fail(400, 'invalid_' + name);
  return value;
}
function record(body, table, create) {
  const allowed = fields[table];
  checkKeys(body, create && table === 'courses' ? [...allowed, 'productID'] : allowed);
  const result = {};
  for (const field of allowed) {
    if (!Object.hasOwn(body, field)) continue;
    const value = body[field];
    if (field === 'isPreview') {
      if (typeof value !== 'boolean') fail(400, 'invalid_preview');
      result.is_preview = value;
    } else if (field === 'sortOrder') {
      result.sort_order = integer(value, 'sort_order');
    } else if (field === 'durationSeconds') {
      result.duration_seconds = value === null ? null : integer(value, 'duration');
    } else {
      if (value !== null && typeof value !== 'string') fail(400, 'invalid_admin_fields');
      const clean = value?.trim() || '';
      if (clean.includes('\0')) fail(400, 'invalid_admin_fields');
      result[textFields[field]] = ['title', 'subtitle', 'description'].includes(field) ? clean : clean || null;
    }
  }
  if ((create || Object.hasOwn(result, 'title')) && !result.title) fail(400, 'title_required');
  if (!Object.keys(result).length) fail(400, 'invalid_admin_fields');
  return result;
}

async function mutate(read, table, id, method, body, filters = {}) {
  const params = method === 'POST' ? { select: 'id' } : { select: 'id', id: 'eq.' + id, ...filters };
  try {
    const rows = await read(endpoint(table, params), { method, body, headers: { Prefer: 'return=representation' } });
    if (!rows.some(row => row.id === id)) fail(409, 'change_not_applied');
    return { id };
  } catch (error) {
    if (error.code === '23514') fail(409, 'course_requirements');
    if (error.code === '23503') fail(409, 'related_records');
    throw error;
  }
}

async function addChild(read, table, parentID, body) {
  const row = record(body, table, true);
  const isSection = table === 'course_sections';
  const id = parentID + (isSection ? '.section.' : '.lesson.') + randomUUID();
  const parentColumn = isSection ? 'course_id' : 'section_id';
  const autoOrder = row.sort_order === undefined;
  for (let attempt = 0; ; attempt++) {
    if (autoOrder) {
      const [last] = await read(endpoint(table, {
        select: 'sort_order', [parentColumn]: 'eq.' + parentID, order: 'sort_order.desc', limit: 1,
      }));
      row.sort_order = (last?.sort_order ?? 0) + 1;
    }
    try {
      return await mutate(read, table, id, 'POST', { ...row, id, [parentColumn]: parentID });
    } catch (error) {
      if (!autoOrder || error.code !== '23505' || attempt >= 2) throw error;
    }
  }
}

function assetType(body) {
  if (body?.assetType !== 'cover' && body?.assetType !== 'video') fail(400, 'invalid_asset_type');
  return assets[body.assetType];
}
function isAssetPath(path, spec) {
  if (typeof path !== 'string') return false;
  const match = /^([A-Za-z0-9._-]+)\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\.([a-z0-9]+)$/u.exec(path);
  return Boolean(match && productPattern.test(match[1]) && Object.hasOwn(spec.mime, match[3]));
}
async function uploadTicket(read, body, base, apiKey) {
  const spec = assetType(body);
  checkKeys(body, [spec.idField, 'assetType', 'fileExtension', 'fileSize', 'contentType']);
  const id = validID(body[spec.idField]);
  const ext = typeof body.fileExtension === 'string' ? body.fileExtension.toLowerCase() : '';
  if (!Object.hasOwn(spec.mime, ext) || spec.mime[ext] !== body.contentType) fail(400, 'unsupported_file_type');
  if (!Number.isInteger(body.fileSize) || body.fileSize < 1 || body.fileSize > spec.maxSize) fail(400, 'invalid_file_size');
  const ticket = await read('/functions/v1/create-admin-' + body.assetType + '-upload', {
    method: 'POST', body: { ...body, fileExtension: ext, [spec.idField]: id },
  });
  if (!isAssetPath(ticket?.path, spec) || typeof ticket?.token !== 'string' || !ticket.token) fail(502, 'invalid_upload_ticket');
  const url = new URL('/storage/v1/object/upload/sign/' + spec.bucket + '/' + ticket.path, base);
  url.searchParams.set('token', ticket.token);
  return { uploadURL: url.href, path: ticket.path, apiKey };
}

async function attachUpload(read, body) {
  const spec = assetType(body);
  checkKeys(body, ['assetType', spec.idField, 'path']);
  const id = validID(body[spec.idField]);
  if (!isAssetPath(body.path, spec)) fail(400, 'invalid_asset_path');
  const cover = body.assetType === 'cover';
  const [target] = await read(endpoint(spec.table, {
    id: 'eq.' + id, select: cover ? 'store_product_id' : 'course_sections(courses(store_product_id))', limit: 1,
  }));
  const productID = cover ? target?.store_product_id : target?.course_sections?.courses?.store_product_id;
  if (!productID) fail(404, 'not_found');
  if (body.path.split('/')[0] !== productID) fail(400, 'invalid_asset_path');
  // The cover bucket is public. Private videos are checked by the publication constraint in Postgres.
  if (cover) await read('/storage/v1/object/info/public/course-covers/' + body.path);
  return mutate(read, spec.table, id, 'PATCH', { [spec.column]: body.path });
}

export async function admin({ method, path, body, user, request, supabaseURL, key }) {
  if (path === '/api/admin/status' && !user) {
    ensureMethod(method, 'GET');
    return { isAdmin: false };
  }
  ensureLogin(user);
  const read = (url, options = {}) => request(url, { method: 'GET', ...options, token: user.accessToken });
  const roles = await read(endpoint('course_admins', { user_id: 'eq.' + user.id, select: 'user_id', limit: 1 }));
  const isAdmin = roles.some(role => role.user_id === user.id);
  if (path === '/api/admin/status') {
    ensureMethod(method, 'GET');
    return { isAdmin };
  }
  if (!isAdmin) fail(403, 'admin_access_required');
  if (path === '/api/admin/uploads' || path === '/api/admin/uploads/attach') {
    ensureMethod(method, 'POST');
    return path.endsWith('/attach') ? attachUpload(read, body) : uploadTicket(read, body, supabaseURL, key);
  }
  if (path === '/api/admin/courses') {
    ensureMethod(method, 'GET', 'POST');
    if (method === 'GET') {
      const select = courseFields + ',course_sections(' + sectionFields + ',lessons(' + lessonFields + ',video_path))';
      const rows = await allRows(read, 'courses', { select, order: 'sort_order.asc,id.asc' });
      return { courses: rows.map(row => courseData(row, supabaseURL, true, true)) };
    }
    const row = record(body, 'courses', true);
    const id = typeof body.productID === 'string' ? body.productID.trim() : '';
    if (!productPattern.test(id)) fail(400, 'invalid_product_id');
    return mutate(read, 'courses', id, 'POST', { ...row, id, store_product_id: id, is_published: false });
  }
  const publication = /^\/api\/admin\/courses\/([^/]+)\/publication$/u.exec(path);
  if (publication) {
    ensureMethod(method, 'PATCH');
    checkKeys(body, ['isPublished']);
    if (typeof body.isPublished !== 'boolean') fail(400, 'invalid_publication');
    return mutate(read, 'courses', routeID(publication[1]), 'PATCH', { is_published: body.isPublished });
  }
  const child = /^\/api\/admin\/(courses|sections)\/([^/]+)\/(sections|lessons)$/u.exec(path);
  if (child) {
    ensureMethod(method, 'POST');
    const section = child[1] === 'courses' && child[3] === 'sections';
    const lesson = child[1] === 'sections' && child[3] === 'lessons';
    if (!section && !lesson) fail(404, 'not_found');
    return addChild(read, section ? 'course_sections' : 'lessons', routeID(child[2]), body);
  }
  const entity = /^\/api\/admin\/(courses|sections|lessons)\/([^/]+)$/u.exec(path);
  if (entity) {
    ensureMethod(method, 'PATCH', 'DELETE');
    const table = entity[1] === 'sections' ? 'course_sections' : entity[1];
    const id = routeID(entity[2]);
    if (method === 'PATCH') return mutate(read, table, id, method, record(body, table, false));
    const filters = table === 'courses' ? { is_published: 'eq.false', cover_path: 'is.null' } : {};
    return mutate(read, table, id, method, undefined, filters);
  }
  fail(404, 'not_found');
}
