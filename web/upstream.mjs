export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; this.code = undefined; }
}

export function supabaseRequest({ supabaseURL, key }) {
  return async (path, { method = 'GET', body = undefined, headers = {}, token = undefined } = {}) => {
    const url = new URL(path, supabaseURL);
    if (url.origin !== supabaseURL || !/^\/(auth|rest|storage|functions)\/v1\//.test(url.pathname)) throw new Error('Invalid API route');
    /** @type {RequestInit} */
    const opts = { method, headers: { 'Content-Type': 'application/json', ...headers, apikey: key, ...(token ? { Authorization: 'Bearer ' + token } : {}) }, redirect: 'error', signal: AbortSignal.timeout(15000) };
    if (body !== undefined) opts.body = JSON.stringify(body);
    let response;
    try { response = await fetch(url, opts); }
    catch { throw new HttpError(503, 'upstream_unavailable'); }
    if (!response.ok) {
      const details = await response.json().catch(() => ({}));
      const error = new HttpError(response.status, 'upstream_error');
      error.code = details.error_code || details.code;
      throw error;
    }
    const raw = await response.text();
    return raw ? JSON.parse(raw) : null;
  };
}
