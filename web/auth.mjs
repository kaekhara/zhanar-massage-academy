import { createHash, randomBytes } from 'node:crypto';
import { HttpError } from './upstream.mjs';

const authPath = '/auth/v1';
const refreshLifetime = 30 * 24 * 60 * 60;
const linkLifetime = 60 * 60;

const publicAuthErrors = new Set(['invalid_credentials', 'email_not_confirmed', 'weak_password',
  'same_password', 'email_exists', 'user_already_exists', 'otp_expired', 'over_sms_send_rate_limit']);

function emailFrom(body) {
  const email = typeof body?.email === 'string' ? body.email.trim() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email)) {
    throw new HttpError(400, 'invalid_email');
  }
  return email;
}

function passwordFrom(body, minimumLength) {
  const password = body?.password;
  if (typeof password !== 'string' || password.length < minimumLength || password.length > 1024) {
    throw new HttpError(400, 'invalid_password');
  }
  return password;
}

function displayNameFrom(body) {
  const name = body?.displayName ?? '';
  if (typeof name !== 'string' || name.trim().length > 120) throw new HttpError(400, 'invalid_display_name');
  return name.trim();
}

function phoneFrom(body) {
  const input = body?.phone;
  if (typeof input === 'string' && input.length <= 30 && /^[+\d ()-]+$/.test(input)) {
    const digits = input.replace(/[+ ()-]/g, '');
    if (/^\d{10}$/.test(digits)) return '+7' + digits;
    if (/^[78]\d{10}$/.test(digits)) return '+7' + digits.slice(1);
  }
  throw new HttpError(400, 'invalid_phone');
}

function identity(user) {
  if (typeof user?.id !== 'string' || !user.id) {
    throw new HttpError(502, 'invalid_auth_response');
  }
  return { id: user.id, email: user.email || null, ...(user.phone ? { phone: user.phone } : {}) };
}

function validTokens(result) {
  const validToken = value => typeof value === 'string' && value.length > 0;
  if (!validToken(result?.refresh_token) || !validToken(result.access_token)) {
    throw new HttpError(502, 'invalid_auth_response');
  }
  identity(result.user);
  return result;
}

export function createAuth({ request: upstream, origin, secure = new URL(origin).protocol === 'https:', phoneEnabled = false }) {
  const callback = new URL('/auth/callback', origin).href;
  const redirectQuery = new URLSearchParams({ redirect_to: callback });
  const prefix = (secure ? '__Host-' : '') + 'zhanar_';
  const refreshing = new Map();

  async function request(path, options) {
    try {
      return await upstream(path, options);
    } catch (error) {
      if (publicAuthErrors.has(error.code)) throw new HttpError(error.status, error.code);
      if (error.code === 'email_address_invalid') throw new HttpError(error.status, 'invalid_email');
      throw error;
    }
  }

  function readCookie(req, name) {
    const key = prefix + name + '=';
    const pair = req.headers.cookie?.split(';').map(item => item.trim()).find(item => item.startsWith(key));
    if (!pair) return '';
    try {
      return decodeURIComponent(pair.slice(key.length));
    } catch {
      return '';
    }
  }

  function setCookie(res, name, value, maxAge) {
    const cookieName = prefix + name;
    const cookie = cookieName + '=' + encodeURIComponent(value) + '; Path=/; HttpOnly; SameSite=Lax; Max-Age=' +
      maxAge + (secure ? '; Secure' : '');
    const previous = res.getHeader('Set-Cookie') ?? [];
    const other = [previous].flat().filter(item => !item.startsWith(cookieName + '='));
    res.setHeader('Set-Cookie', [...other, cookie]);
  }

  function clearSession(res) {
    setCookie(res, 'access', '', 0);
    setCookie(res, 'refresh', '', 0);
  }

  function storeSession(res, result) {
    validTokens(result);
    const expiresIn = Number(result.expires_in);
    const lifetime = Number.isFinite(expiresIn) && expiresIn > 0 ? Math.floor(expiresIn) : 3600;
    setCookie(res, 'access', result.access_token, lifetime);
    setCookie(res, 'refresh', result.refresh_token, refreshLifetime);
    return { ...identity(result.user), accessToken: result.access_token };
  }

  async function startSession(res, result) {
    validTokens(result);
    const displayName = result.user.user_metadata?.display_name;
    // Populate a new profile once and preserve any edits made on iOS or the web.
    await request('/rest/v1/profiles?on_conflict=id', {
      method: 'POST',
      headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' },
      token: result.access_token,
      body: { id: result.user.id, display_name: typeof displayName === 'string' ? displayName.trim() : '' }
    });
    storeSession(res, result);
    return { user: identity(result.user) };
  }

  function refresh(refreshToken) {
    let operation = refreshing.get(refreshToken);
    if (!operation) {
      operation = request(authPath + '/token?grant_type=refresh_token', {
        method: 'POST', body: { refresh_token: refreshToken }
      }).finally(() => refreshing.delete(refreshToken));
      refreshing.set(refreshToken, operation);
    }
    return operation;
  }

  async function session(req, res) {
    const accessToken = readCookie(req, 'access');
    if (accessToken) {
      try {
        const user = await request(authPath + '/user', { method: 'GET', token: accessToken });
        return { ...identity(user), accessToken };
      } catch (error) {
        if (![401, 403].includes(error.status)) throw error;
      }
    }
    const refreshToken = readCookie(req, 'refresh');
    if (refreshToken) {
      try {
        return storeSession(res, await refresh(refreshToken));
      } catch (error) {
        if (![400, 401, 403, 422].includes(error.status)) throw error;
      }
    }
    if (accessToken || refreshToken) clearSession(res);
    return null;
  }

  function redirect(res, flow) {
    res.writeHead(303, {
      Location: '/?flow=' + flow,
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer'
    });
    res.end();
  }

  async function emailFlow(res, body, flow) {
    const email = emailFrom(body);
    const verifier = randomBytes(32).toString('base64url');
    const payload = {
      email, code_challenge: createHash('sha256').update(verifier).digest('base64url'),
      code_challenge_method: 's256'
    };
    if (flow === 'signup') {
      payload.password = passwordFrom(body, 8);
      payload.data = { display_name: displayNameFrom(body) };
    }
    const endpoint = flow === 'signup' ? '/signup' : '/recover';
    const result = await request(authPath + endpoint + '?' + redirectQuery, { method: 'POST', body: payload });
    if (flow === 'signup' && result?.access_token) {
      return startSession(res, result);
    }
    setCookie(res, 'pkce', flow + '.' + verifier, linkLifetime);
    return flow === 'signup' ? { confirmationRequired: true } : { ok: true };
  }

  async function confirm(req, res) {
    const query = new URL(req.url, origin).searchParams;
    const code = query.get('code');
    const pending = /^(signup|recovery)\.([A-Za-z0-9_-]{43})$/.exec(readCookie(req, 'pkce'));
    if (!pending || !code || code.length > 2048 || query.has('error') || query.has('error_code')) {
      return redirect(res, 'invalid');
    }

    let result;
    try {
      result = await request(authPath + '/token?grant_type=pkce', {
        method: 'POST', body: { auth_code: code, code_verifier: pending[2] }
      });
    } catch (error) {
      if (![400, 401, 403, 404, 422].includes(error.status)) throw error;
      return redirect(res, 'invalid');
    }

    await startSession(res, result);
    setCookie(res, 'pkce', '', 0);
    return redirect(res, pending[1] === 'recovery' ? 'recovery' : 'confirmed');
  }

  async function handle({ req, res, path, body }) {
    if (path === '/auth/callback') {
      if (req.method !== 'GET') throw new HttpError(405, 'method_not_allowed');
      return confirm(req, res);
    }
    if (req.method !== 'POST') throw new HttpError(405, 'method_not_allowed');

    switch (path) {
      case '/api/auth/login': {
        const payload = { email: emailFrom(body), password: passwordFrom(body, 1) };
        const result = await request(authPath + '/token?grant_type=password', { method: 'POST', body: payload });
        return startSession(res, result);
      }
      case '/api/auth/signup':
        return emailFlow(res, body, 'signup');
      case '/api/auth/recover':
        return emailFlow(res, body, 'recovery');
      case '/api/auth/password': {
        const password = passwordFrom(body, 8);
        const current = await session(req, res);
        if (!current) throw new HttpError(401, 'authentication_required');
        await request(authPath + '/user', { method: 'PUT', body: { password }, token: current.accessToken });
        return { ok: true };
      }
      case '/api/auth/phone':
      case '/api/auth/verify-phone': {
        if (!phoneEnabled) throw new HttpError(404, 'phone_login_disabled');
        const phone = phoneFrom(body);
        if (path === '/api/auth/phone') {
          await request(authPath + '/otp', { method: 'POST',
            body: { phone, channel: 'sms', create_user: true, data: { display_name: displayNameFrom(body) } }
          });
          return { ok: true };
        }
        if (typeof body.code !== 'string' || !/^\d{6}$/.test(body.code)) throw new HttpError(400, 'invalid_code');
        const result = await request(authPath + '/verify', {
          method: 'POST', body: { phone, type: 'sms', token: body.code }
        });
        return startSession(res, result);
      }
      case '/api/auth/delete': {
        if (body?.confirm !== true) throw new HttpError(400, 'confirmation_required');
        const current = await session(req, res);
        if (!current) throw new HttpError(401, 'authentication_required');
        try {
          const result = await request('/functions/v1/delete-account', { method: 'POST', token: current.accessToken });
          if (result?.deleted !== true) throw new HttpError(502, 'account_deletion_unconfirmed');
          return { deleted: true };
        } finally {
          // The function revokes the account's sessions before committing the deletion.
          clearSession(res);
          setCookie(res, 'pkce', '', 0);
        }
      }
      case '/api/auth/logout': {
        try {
          const current = await session(req, res);
          if (current) {
            try {
              await request(authPath + '/logout?scope=local', { method: 'POST', token: current.accessToken });
            } catch (error) {
              if (![401, 403, 404].includes(error.status)) throw error;
            }
          }
        } finally {
          clearSession(res);
          setCookie(res, 'pkce', '', 0);
        }
        return { ok: true };
      }
      default:
        throw new HttpError(404, 'not_found');
    }
  }

  return { session, handle };
}
