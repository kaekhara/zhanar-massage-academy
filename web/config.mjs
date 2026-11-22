import { isIP } from 'node:net';

function originSetting(value, name, production) {
  const url = new URL(value);
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (url.origin !== value || (url.protocol !== 'https:' && !(loopback && !production && url.protocol === 'http:'))) {
    throw new Error(name + ' must be an HTTPS origin (HTTP loopback is allowed in development)');
  }
  return url.origin;
}

function optionalLink(value) {
  if (!value) return null;
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('School links must use HTTPS');
  return url.href;
}

export function readConfig(env = process.env) {
  const production = env.NODE_ENV === 'production';
  const port = Number(env.PORT || 4173);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  const origin = originSetting(env.APP_ORIGIN || 'http://localhost:' + port, 'APP_ORIGIN', production);
  const supabaseURL = originSetting(env.SUPABASE_URL, 'SUPABASE_URL', production);
  const key = env.SUPABASE_PUBLISHABLE_KEY || '';
  if (!/^sb_publishable_[a-zA-Z0-9_-]+$/.test(key)) throw new Error('SUPABASE_PUBLISHABLE_KEY must be a public sb_publishable_ key');
  const host = env.HOST || '127.0.0.1';
  if (!isIP(host) && host !== 'localhost') throw new Error('Invalid HOST');
  const links = { support: optionalLink(env.SUPPORT_URL), privacy: optionalLink(env.PRIVACY_URL),
    terms: optionalLink(env.TERMS_URL), appStore: optionalLink(env.APP_STORE_URL) };
  const phoneEnabled = env.SUPABASE_PHONE_ENABLED === 'true';
  return { origin, supabaseURL, key, port, host, links, phoneEnabled, trustedProxy: env.TRUSTED_PROXY_IP, production, secure: origin.startsWith('https://') };
}
