import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createAuth } from '../auth.mjs';

const origin = 'https://academy.example';
const user = { id: 'user-id', email: 'student@example.com', user_metadata: { display_name: 'Жанар' } };
const tokens = { user, access_token: 'access-secret', refresh_token: 'refresh-secret', expires_in: 900 };
const profilePath = '/rest/v1/profiles?on_conflict=id';

function response() {
  const headers = new Map();
  return {
    getHeader: key => headers.get(key.toLowerCase()),
    setHeader: (key, value) => headers.set(key.toLowerCase(), value),
    writeHead(status, values) {
      this.status = status;
      Object.entries(values).forEach(([key, value]) => this.setHeader(key, value));
    },
    end() { this.ended = true; }
  };
}

function req(url, cookie = '', method = 'POST') {
  return { method, url, headers: { cookie } };
}

function cookies(res) {
  return (res.getHeader('Set-Cookie') || []).map(line => line.split(';')[0]).join('; ');
}

function fixture(fn) {
  const calls = [];
  const auth = createAuth({ origin, request: async (path, options) => {
    calls.push({ path, ...options });
    return fn(path, options);
  } });
  async function send(path, body, cookie = '', method = 'POST') {
    const res = response();
    const result = await auth.handle({ req: req(path, cookie, method), res, path: path.split('?')[0], body });
    return { res, result };
  }
  return { calls, send, auth };
}

function upstreamError(status, code) {
  return Object.assign(new Error('upstream_error'), { status, code });
}

test('login creates missing profile under the user JWT and exposes only identity', async () => {
  const { send, calls } = fixture(path => path === profilePath ? null : tokens);
  const { result, res } = await send('/api/auth/login', {
    email: ' student@example.com ', password: 'iOS pw', id: 'someone-else'
  });
  assert.deepEqual(result, { user: { id: user.id, email: user.email } });
  assert.deepEqual(calls, [
    { path: '/auth/v1/token?grant_type=password', method: 'POST', body: { email: user.email, password: 'iOS pw' } },
    { path: profilePath, method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' },
      token: tokens.access_token, body: { id: user.id, display_name: 'Жанар' } }
  ]);
  const set = res.getHeader('Set-Cookie');
  assert.equal(set.length, 2);
  for (const value of set) {
    assert.match(value, /^__Host-zhanar_(access|refresh)=/);
    assert.match(value, /Path=\/; HttpOnly; SameSite=Lax; Max-Age=\d+; Secure$/);
  }
  assert.match(set[0], /Max-Age=900;/);
});

test('password recovery uses PKCE and fixed origin across email, callback, then password update', async () => {
  let recovered = false;
  const { send, calls } = fixture((path, options) => {
    if (path.startsWith('/auth/v1/recover?')) return {};
    if (path.endsWith('grant_type=pkce')) {
      assert.equal(options.body.auth_code, 'issued-code');
      const challenge = createHash('sha256').update(options.body.code_verifier).digest('base64url');
      assert.equal(challenge, calls[0].body.code_challenge);
      recovered = true;
      return tokens;
    }
    if (path === profilePath) return null;
    if (path === '/auth/v1/user' && options.token === tokens.access_token) return user;
    assert.fail('Unexpected GoTrue call: ' + path);
  });
  const recovery = await send('/api/auth/recover', { email: user.email, redirect_to: 'https://other.example' });
  assert.deepEqual(recovery.result, { ok: true });
  assert.equal(new URL(calls[0].path, origin).searchParams.get('redirect_to'), origin + '/auth/callback');
  assert.equal(calls[0].body.code_challenge_method, 's256');
  const callback = await send('/auth/callback?code=issued-code&next=https://other.example', undefined, cookies(recovery.res), 'GET');
  assert.equal(recovered, true);
  assert.equal(callback.res.status, 303);
  assert.equal(callback.res.getHeader('Location'), '/?flow=recovery');
  assert.equal(callback.res.getHeader('Referrer-Policy'), 'no-referrer');
  assert.ok(callback.res.ended);
  assert.match(callback.res.getHeader('Set-Cookie').join(' '), /pkce=;[^;]*; HttpOnly; SameSite=Lax; Max-Age=0/);
  const changed = await send('/api/auth/password', { password: 'replacement' }, cookies(callback.res));
  assert.deepEqual(changed.result, { ok: true });
  assert.deepEqual(calls.at(-1), {
    path: '/auth/v1/user', method: 'PUT', body: { password: 'replacement' }, token: tokens.access_token
  });
});

test('signup handles both auto-confirmed and email-confirmed projects', async () => {
  for (const autoConfirm of [false, true]) {
    const { send, calls } = fixture((path) => {
      if (path.startsWith('/auth/v1/signup?')) return autoConfirm ? tokens : { id: user.id };
      if (path.endsWith('grant_type=pkce')) return tokens;
      if (path === profilePath) return null;
      assert.fail(path);
    });
    const body = { email: user.email, password: '12345_secure', displayName: ' Жанар ' };
    const signup = await send('/api/auth/signup', body);
    assert.deepEqual(calls[0].body.data, { display_name: 'Жанар' });
    if (autoConfirm) assert.deepEqual(signup.result.user, { id: user.id, email: user.email });
    else {
      assert.deepEqual(signup.result, { confirmationRequired: true });
      assert.doesNotMatch(cookies(signup.res), /zhanar_(access|refresh)=/);
      const ok = await send('/auth/callback?code=signup', undefined, cookies(signup.res), 'GET');
      assert.equal(ok.res.getHeader('Location'), '/?flow=confirmed');
    }
  }
});

test('an invalid or expired confirmation link never authenticates the browser', async () => {
  const { send, calls } = fixture(() => { throw upstreamError(400, 'bad_code_verifier'); });
  const unknown = await send('/auth/callback?code=unbound', undefined, '', 'GET');
  assert.equal(unknown.res.getHeader('Location'), '/?flow=invalid');
  assert.equal(calls.length, 0);
  const jar = '__Host-zhanar_pkce=recovery.' + 'a'.repeat(43);
  const invalid = await send('/auth/callback?code=wrong', undefined, jar, 'GET');
  assert.equal(invalid.res.getHeader('Location'), '/?flow=invalid');
  assert.equal(calls.length, 1);
  assert.equal(invalid.res.getHeader('Set-Cookie'), undefined);
});

test('overlapping requests share a refresh and see the same new user session', async () => {
  let finishRefresh;
  const wait = new Promise(resolve => { finishRefresh = resolve; });
  const { auth, calls } = fixture(() => wait);
  const request = req('/api/session', '__Host-zhanar_refresh=expired-pair', 'GET');
  const responses = [response(), response()];
  const lookups = responses.map(res => auth.session(request, res));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.refresh_token, 'expired-pair');
  finishRefresh(tokens);
  const sessions = await Promise.all(lookups);
  assert.deepEqual(sessions[0], { id: user.id, email: user.email, accessToken: tokens.access_token });
  assert.deepEqual(sessions[1], sessions[0]);
  assert.equal(cookies(responses[0]), cookies(responses[1]));
});

test('revoked refresh tokens clear browser state while an upstream outage leaves cookies in place', async () => {
  for (const status of [400, 503]) {
    const { auth, calls } = fixture(path => { throw upstreamError(path === '/auth/v1/user' ? 401 : status); });
    const res = response();
    const lookup = auth.session(req('/api/session', '__Host-zhanar_access=expired; __Host-zhanar_refresh=old'), res);
    if (status === 400) {
      assert.equal(await lookup, null);
      const lines = res.getHeader('Set-Cookie');
      assert.equal(lines.length, 2);
      assert.ok(lines.every(line => line.includes('Max-Age=0')));
    } else {
      await assert.rejects(lookup, { status: 503 });
      assert.equal(res.getHeader('Set-Cookie'), undefined);
    }
    assert.deepEqual(calls.map(call => call.path), ['/auth/v1/user', '/auth/v1/token?grant_type=refresh_token']);
  }
});

test('logout revokes only the browser session and clears all local credentials', async () => {
  const { send, calls } = fixture(path => path === '/auth/v1/user' ? user : null);
  const { res, result } = await send('/api/auth/logout', {}, '__Host-zhanar_access=access-secret');
  assert.deepEqual(result, { ok: true });
  assert.deepEqual(calls.at(-1), { path: '/auth/v1/logout?scope=local', method: 'POST', token: tokens.access_token });
  assert.ok(res.getHeader('Set-Cookie').every(value => value.includes('Max-Age=0')));
  const repeated = await send('/api/auth/logout', {});
  assert.deepEqual(repeated.result, { ok: true });
  assert.equal(calls.length, 2);
});

test('invalid inputs and anonymous password changes fail before forwarding to GoTrue', async () => {
  const { send, calls } = fixture(() => assert.fail('unexpected upstream call'));
  await assert.rejects(send('/api/auth/signup', { email: user.email, password: 'short' }), { status: 400 });
  await assert.rejects(send('/api/auth/login', { email: 'bad address', password: 'pw' }), { status: 400 });
  await assert.rejects(send('/api/auth/password', { password: 'replacement' }), { status: 401 });
  await assert.rejects(send('/api/auth/logout', undefined, '', 'GET'), { status: 405 });
  assert.equal(calls.length, 0);
});

test('login errors expose a localizable code without upstream details', async () => {
  const { send } = fixture(() => {
    throw Object.assign(new Error('sensitive upstream response'), { status: 400, code: 'invalid_credentials' });
  });
  await assert.rejects(send('/api/auth/login', { email: user.email, password: 'incorrect' }),
    { status: 400, message: 'invalid_credentials' });
});

test('SMS is disabled by default, and verification validates the six-digit code', async () => {
  const disabled = fixture(() => assert.fail('disabled SMS must not call upstream'));
  await assert.rejects(disabled.send('/api/auth/phone', { phone: '+77001234567' }), { status: 404 });
  const enabled = createAuth({ origin, phoneEnabled: true, request: async () => assert.fail('invalid OTP sent') });
  for (const body of [{ phone: 'bad', code: '000000' }, { phone: '87001234567', code: '12345' }]) {
    const path = '/api/auth/verify-phone';
    await assert.rejects(enabled.handle({ req: req(path), res: response(), path, body }), { status: 400 });
  }
});

test('Kazakhstan SMS send and verify use real GoTrue request shapes', async () => {
  const phone = '+77001234567';
  const phoneUser = { id: user.id, phone, email: '', user_metadata: { display_name: 'Жанар' } };
  const calls = [];
  const auth = createAuth({ origin, phoneEnabled: true, request: async (path, options) => {
    calls.push({ path, ...options });
    return path === '/auth/v1/verify' ? { ...tokens, user: phoneUser } : {};
  } });
  for (const [path, body] of [
    ['/api/auth/phone', { phone: '8 (700) 123-45-67', displayName: ' Жанар ' }],
    ['/api/auth/verify-phone', { phone: '7001234567', code: '000137' }]
  ]) {
    const result = await auth.handle({ path, body, req: req(path), res: response() });
    if (path.endsWith('verify-phone')) assert.deepEqual(result, { user: { id: user.id, email: null, phone } });
  }
  assert.deepEqual(calls[0].body, { phone, channel: 'sms', create_user: true, data: { display_name: 'Жанар' } });
  assert.deepEqual(calls[1].body, { phone, type: 'sms', token: '000137' });
});

test('deletion requires explicit confirmation and delegates only the authenticated identity', async () => {
  const { send, calls } = fixture(path => path === '/auth/v1/user' ? user : { deleted: true });
  const cookie = '__Host-zhanar_access=access-secret';
  await assert.rejects(send('/api/auth/delete', {}, cookie), { status: 400 });
  await assert.rejects(send('/api/auth/delete', { confirm: true }), { status: 401 });
  assert.equal(calls.length, 0);
  const removed = await send('/api/auth/delete', { confirm: true, userId: 'different-user' }, cookie);
  assert.deepEqual(removed.result, { deleted: true });
  assert.deepEqual(calls.at(-1), { path: '/functions/v1/delete-account', method: 'POST', token: tokens.access_token });
  assert.ok(removed.res.getHeader('Set-Cookie').every(value => value.includes('Max-Age=0')));
});

test('an unconfirmed upstream deletion is reported as a failure and clears stale credentials', async () => {
  const { auth } = fixture(path => path === '/auth/v1/user' ? user : {});
  const res = response();
  const path = '/api/auth/delete';
  await assert.rejects(auth.handle({ path, body: { confirm: true }, req: req(path, '__Host-zhanar_access=live'), res }),
    { status: 502 });
  assert.ok(res.getHeader('Set-Cookie').every(value => value.includes('Max-Age=0')));
});
