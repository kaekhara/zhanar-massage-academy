import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readConfig } from './config.mjs';
import { HttpError, supabaseRequest } from './upstream.mjs';
import { createAuth } from './auth.mjs';
import { admin } from './admin.mjs';
import { academy } from './academy.mjs';

const publicDir = fileURLToPath(new URL('./public/', import.meta.url));
const page = /^\/(?:|catalog|library|profile|admin|privacy|help|login|signup|recover|password|courses\/[^/]+(?:\/lessons\/[^/]+)?)$/;
const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.mjs':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.svg':'image/svg+xml', '.webp':'image/webp', '.ico':'image/x-icon', '.woff2':'font/woff2', '.txt':'text/plain' };

async function readBody(req) {
  if (req.headers['content-type']?.split(';')[0].trim().toLowerCase() !== 'application/json') throw new HttpError(415, 'json_required');
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 16384) throw new HttpError(413,'body_too_large');
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new HttpError(400,'invalid_json'); }
}

function send(res, status, data) {
  res.writeHead(status, { 'Content-Type':'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}

export function makeServer(config, request = supabaseRequest(config)) {
  const auth = createAuth({request, origin:config.origin, secure:config.secure,phoneEnabled:config.phoneEnabled});
  const buckets = new Map();
  const windowMs = 60000;
  function limit(req, group, max) {
    let addr = req.socket.remoteAddress;
    // Enable only behind a proxy which replaces X-Real-IP on every request.
    if (config.trustedProxy && addr === config.trustedProxy) addr = req.headers['x-real-ip'] || addr;
    const key = group + ':' + addr;
    const now = Date.now();
    const entry = buckets.get(key);
    if (!entry || now >= entry.until) {
      if (!entry && buckets.size >= 50000) throw new HttpError(429,'rate_limited');
      buckets.set(key, {until:now + windowMs, count:1});
    } else if (++entry.count > max) throw new HttpError(429,'rate_limited');
  }
  const sweep = setInterval(() => {
    for (const [key, value] of buckets) if (Date.now() >= value.until) buckets.delete(key);
  }, windowMs);
  sweep.unref();
  const server = createServer({ requestTimeout:30000,headersTimeout:15000 }, async (req,res) => {
    let category = 'page';
    const backend = config.supabaseURL;
    const storage = new URL(backend);
    if (storage.hostname.endsWith('.supabase.co')) storage.hostname = storage.hostname.replace(/\.supabase\.co$/, '.storage.supabase.co');
    res.setHeader('Content-Security-Policy', "default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self'; style-src 'self'; connect-src 'self' " + backend + ' ' + storage.origin + "; img-src 'self' " + backend + ' ' + storage.origin + "; media-src 'self' " + backend + ' ' + storage.origin);
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('X-Frame-Options','DENY');
    res.setHeader('Cache-Control','no-store');
    if (config.secure) res.setHeader('Strict-Transport-Security','max-age=31536000');
    try {
      const path = new URL(req.url, config.origin).pathname;
      const method = req.method;
      if (path.startsWith('/api/') || path === '/auth/callback') {
        category = path.startsWith('/api/auth/') || path === '/auth/callback' ? 'auth' : 'api';
        limit(req, 'api', 240);
        let body = {};
        if (method !== 'GET') {
          if (!['PATCH','POST','DELETE'].includes(method)) throw new HttpError(405,'method_not_allowed');
          if (req.headers.origin !== config.origin) throw new HttpError(403,'origin_rejected');
          limit(req, category + '-write', category === 'auth' ? 12 : 90);
          body = method === 'DELETE' && !req.headers['content-type'] ? {} : await readBody(req);
        }
        if (category === 'auth') {
          if (method !== (path === '/auth/callback' ? 'GET' : 'POST')) throw new HttpError(405,'method_not_allowed');
          const result = await auth.handle({req,res,path,body});
          if (!res.writableEnded) {
            console.info(JSON.stringify({event:'auth_request_handled',action:path.split('/').pop()}));
            send(res,200,result);
          }
          return;
        }
        if (path === '/api/settings' && method === 'GET') return send(res,200,{links:config.links,phoneEnabled:config.phoneEnabled});
        const user = await auth.session(req,res);
        if (path === '/api/session') {
          if (method !== 'GET') throw new HttpError(405,'method_not_allowed');
          return send(res,200,{user:user ? {id:user.id,email:user.email,phone:user.phone} : null,phoneEnabled:config.phoneEnabled});
        }
        if (path.startsWith('/api/admin/')) {
          const result = await admin({method,path,body,user,request,supabaseURL:backend,key:config.key});
          if (method !== 'GET') console.info(JSON.stringify({event:'admin_change',method,area:path.split('/')[3]}));
          return send(res,200,result);
        }
        return send(res,200,await academy({method,path,body,user,request,supabaseURL:backend}));
      }
      if (method !== 'GET' && method !== 'HEAD') throw new HttpError(405,'method_not_allowed');
      let relative;
      try { relative = decodeURIComponent(path.slice(1)); } catch { throw new HttpError(400,'invalid_path'); }
      if (page.test(path)) relative = 'index.html';
      const file = resolve(publicDir, relative);
      if (!file.startsWith(resolve(publicDir) + sep) || relative.split('/').some(s=>s.startsWith('.')) || !types[extname(file)]) throw new HttpError(404,'not_found');
      const info = await stat(file).catch(()=>null);
      if (!info?.isFile()) throw new HttpError(404,'not_found');
      res.writeHead(200, {'Content-Type':types[extname(file)],'Content-Length':info.size,'Cache-Control':extname(file)==='.html'?'no-cache':'public, max-age=300'});
      if (method === 'HEAD') return res.end();
      const stream = createReadStream(file);
      res.on('close', () => stream.destroy());
      stream.on('error', () => res.destroy()).pipe(res);
    } catch (err) {
      const status = Number.isInteger(err.status) && err.status >= 400 && err.status <= 599 ? err.status : 500;
      // Never log callback URLs, email, cookies, upstream response bodies or tokens.
      if (status >= 500 || category === 'auth') console.warn(JSON.stringify({event:'request_failed',category,status}));
      if (status === 429) res.setHeader('Retry-After','60');
      const knownCode = /^[a-z][a-z0-9_]{1,60}$/.test(err.message);
      if (!res.headersSent) send(res,status,{error:knownCode ? err.message : 'request_failed'});
      else res.destroy();
    }
  });
  server.on('close',()=>clearInterval(sweep));
  return server;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const config = readConfig();
  makeServer(config).listen(config.port, config.host, () => console.log('ZHANAR ' + config.origin));
}
