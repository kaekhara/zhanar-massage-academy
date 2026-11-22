import test from 'node:test';
import assert from 'node:assert/strict';
import { academy } from '../academy.mjs';

const user = { id: 'user-1', accessToken: 'student-token' };
const supabaseURL = 'https://example.supabase.co';
const product = 'academy.anatomy';
const lesson = {
  id: 'intro', title: 'Кіріспе', title_ru: 'Введение', description: '', description_ru: '',
  duration_seconds: 60, sort_order: 0, is_preview: true,
};
const row = {
  id: 'anatomy', store_product_id: product, title: 'Анатомия', title_ru: 'Анатомия',
  sort_order: 1, is_published: true, cover_path: product + '/cover one.png',
  course_sections: [{
    id: 'section', title: 'I', sort_order: 0,
    lessons: [{ ...lesson, id: 'study', sort_order: 1, duration_seconds: null }, lesson],
  }],
};
function videoLesson({ owned = false, published = true, preview = false, path = product + '/Lesson one.mp4' } = {}) {
  return {
    ...lesson, is_preview: preview, video_path: path,
    course_sections: { courses: {
      is_published: published, store_product_id: product, verified_purchases: owned ? [{ product_id: product }] : [],
    } },
  };
}

function harness(responses) {
  const calls = [];
  async function request(path, options) {
    calls.push({ url: new URL(path, supabaseURL), ...options });
    assert.ok(calls.length <= responses.length, 'Unexpected backend call to ' + path);
    const response = responses[calls.length - 1];
    if (response instanceof Error) throw response;
    return response;
  }
  const run = (path, params = {}) => academy({ method: 'GET', path, user, supabaseURL, request, ...params });
  return { run, calls };
}

test('guest catalog reads published bilingual summaries with public covers and no private columns', async () => {
  const { run, calls } = harness([[row]]);
  const { courses: [course] } = await run('/api/courses', { user: null });
  assert.equal(course.titleRu, row.title_ru);
  assert.equal(course.owned, false);
  assert.equal(course.coverURL, supabaseURL + '/storage/v1/object/public/course-covers/academy.anatomy/cover%20one.png');
  assert.equal(course.lessonCount, 2);
  assert.equal(course.durationSeconds, 60);
  assert.ok(!('sections' in course));
  assert.equal(calls[0].token, undefined);
  assert.equal(calls[0].url.searchParams.get('is_published'), 'eq.true');
  assert.doesNotMatch(calls[0].url.searchParams.get('select'), /video_path|verified_purchases/);
});

test('course details sort lessons and preserve encoded identifiers as one filter', async () => {
  const { run, calls } = harness([[row]]);
  const { course } = await run('/api/courses/name%20%26%20level%202');
  assert.deepEqual(course.sections[0].lessons.map(item => item.id), ['intro', 'study']);
  assert.equal(course.sections[0].lessons[0].isPreview, true);
  assert.equal(calls[0].url.searchParams.get('id'), 'eq.name & level 2');
  assert.equal(calls[0].url.searchParams.get('verified_purchases.user_id'), 'eq.' + user.id);
});

test('library includes archived purchases and filters active purchases of the current user', async () => {
  const { run, calls } = harness([[{ ...row, is_published: false, verified_purchases: [{ product_id: product }] }]]);
  const { courses: [course] } = await run('/api/library');
  assert.equal(course.owned, true);
  const query = calls[0].url.searchParams;
  assert.match(query.get('select'), /verified_purchases!inner\(product_id\)/u);
  assert.equal(query.get('verified_purchases.revoked_at'), 'is.null');
  assert.equal(query.get('verified_purchases.user_id'), 'eq.user-1');
  assert.equal(calls[0].token, user.accessToken);
  assert.ok(!query.has('is_published'));
});

test('a draft visible to an admin remains unavailable in the student-facing course view', async () => {
  const { run } = harness([[{ ...row, is_published: false, verified_purchases: [] }]]);
  await assert.rejects(run('/api/courses/anatomy'), { status: 404 });
});

test('signed lesson video uses the same user token for entitlement lookup and storage', async () => {
  for (const settings of [{ preview: true }, { published: false, owned: true }]) {
    const signed = '/object/sign/course-videos/academy.anatomy/Lesson%20one.mp4?token=signed';
    const { run, calls } = harness([[videoLesson(settings)], { signedURL: signed }]);
    assert.deepEqual(await run('/api/lessons/intro/video'), { url: supabaseURL + '/storage/v1' + signed });
    assert.equal(calls[1].url.pathname, '/storage/v1/object/sign/course-videos/academy.anatomy/Lesson%20one.mp4');
    assert.equal(calls[1].method, 'POST');
    assert.deepEqual(calls[1].body, { expiresIn: 3600 });
    assert.ok(calls.every(call => call.token === user.accessToken));
    const query = calls[0].url.searchParams;
    assert.equal(query.get('course_sections.courses.verified_purchases.revoked_at'), 'is.null');
  }
});

test('protected, unpublished, missing and incorrectly configured videos never reach storage', async () => {
  for (const [rows, status] of [
    [[videoLesson({})], 403], [[videoLesson({ preview: true, published: false })], 404],
    [[], 404], [[videoLesson({ owned: true, path: 'unrelated/lesson.mp4' })], 404],
    [[videoLesson({ owned: true, path: product + '/../other.mp4' })], 404],
  ]) {
    const { run, calls } = harness([rows]);
    await assert.rejects(run('/api/lessons/intro/video'), { status });
    assert.equal(calls.length, 1);
  }
});

test('profile name upsert uses the session user and trims whitespace', async () => {
  const { run, calls } = harness([[{ display_name: 'Жанар' }], null]);
  assert.deepEqual(await run('/api/profile'), { displayName: 'Жанар' });
  assert.deepEqual(await run('/api/profile', { method: 'PATCH', body: { displayName: ' Жанар ', id: 'user-2' } }), { displayName: 'Жанар' });
  assert.equal(calls[0].url.searchParams.get('id'), 'eq.user-1');
  assert.equal(calls[1].body.id, user.id);
  assert.equal(calls[1].body.display_name, 'Жанар');
  assert.match(calls[1].headers.Prefer, /merge-duplicates/);
  for (const name of [null, {}, ' ', 'a'.repeat(101)]) {
    await assert.rejects(run('/api/profile', { method: 'PATCH', body: { displayName: name } }), { status: 400 });
  }
});

test('completing lessons is idempotent, limited to owners and scoped to the signed-in student', async () => {
  const { run, calls } = harness([[videoLesson({ owned: true })], null, [videoLesson({ preview: true })]]);
  const params = { method: 'POST', body: { lessonID: 'intro', user_id: 'someone-else' } };
  assert.deepEqual(await run('/api/progress', params), { lessonID: 'intro', completed: true });
  assert.equal(calls[1].url.searchParams.get('on_conflict'), 'user_id,lesson_id');
  assert.match(calls[1].headers.Prefer, /ignore-duplicates/);
  assert.deepEqual(calls[1].body, { user_id: user.id, lesson_id: 'intro' });
  await assert.rejects(run('/api/progress', params), { status: 403 });
  assert.equal(calls.length, 3);
});

test('progress reads subsequent pages and preserves all lesson IDs', async () => {
  const first = Array.from({ length: 200 }, (_, n) => ({ lesson_id: 'lesson-' + n }));
  const { run, calls } = harness([first, [{ lesson_id: 'last' }]]);
  const response = await run('/api/progress');
  assert.equal(response.completedLessonIDs.length, 201);
  assert.equal(response.completedLessonIDs.at(-1), 'last');
  assert.equal(calls[1].url.searchParams.get('offset'), '200');
  assert.ok(calls.every(call => call.url.searchParams.get('user_id') === 'eq.user-1'));
});

test('resume reads and writes shared iOS records including original playback timestamps', async () => {
  const stamp = '2025-01-02T09:30:00.000Z';
  const { run, calls } = harness([[{ lesson_id: 'intro', position_seconds: 8.5, updated_at: stamp }], [videoLesson({ preview: true })], null]);
  assert.deepEqual(await run('/api/resume'), { positions: [{ lessonID: 'intro', positionSeconds: 8.5, updatedAt: stamp }] });
  const params = { method: 'POST', body: { lessonID: 'intro', positionSeconds: 8.5, updatedAt: stamp } };
  assert.deepEqual(await run('/api/resume', params), { saved: true });
  assert.deepEqual(calls[2].body, { user_id: user.id, lesson_id: 'intro', position_seconds: 8.5, updated_at: stamp });
  assert.equal(calls[2].url.searchParams.get('on_conflict'), 'user_id,lesson_id');
  await assert.rejects(run('/api/resume', { method: 'POST', body: { lessonID: 'intro', positionSeconds: -1 } }), { status: 400 });
});

test('authentication, method and identifier checks run before contacting Supabase', async () => {
  const { run, calls } = harness([]);
  for (const path of ['/api/library', '/api/profile', '/api/progress', '/api/resume', '/api/lessons/intro/video']) {
    await assert.rejects(run(path, { user: null }), { status: 401 });
  }
  await assert.rejects(run('/api/courses', { method: 'PUT' }), { status: 405 });
  await assert.rejects(run('/api/profile', { method: 'DELETE' }), { status: 405 });
  await assert.rejects(run('/api/courses/%'), { status: 400 });
  await assert.rejects(run('/api/progress', { method: 'POST', body: {} }), { status: 400 });
  assert.equal(calls.length, 0);
});
