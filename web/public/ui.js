const languageKey = 'zhanar-language';
const initialLanguage = () => {
  try {
    const saved = new URLSearchParams(location.search).get('lang') || localStorage.getItem(languageKey);
    if (['kk', 'ru'].includes(saved)) return saved;
  } catch { /* Storage is optional. */ }
  return navigator.language?.startsWith('kk') ? 'kk' : 'ru';
};
export const language = initialLanguage();
export const t = (ru, kk) => language === 'kk' ? kk : ru;
document.documentElement.lang = language;
export const localized = (item, key) => t(item[key + 'Ru'] || item[key], item[key] || item[key + 'Ru']) || '';
export function changeLanguage(value) {
  try { localStorage.setItem(languageKey, value); }
  catch { const url = new URL(location.href); url.searchParams.set('lang', value); location.assign(url.href); return; }
  location.reload();
}

/** @template {keyof HTMLElementTagNameMap} T @param {T} tag @param {Record<string, any>} properties @param {...any} children @returns {HTMLElementTagNameMap[T]} */
export function el(tag, properties = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(properties)) {
    if (value == null || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : String(value));
  }
  for (const child of children.flat()) {
    if (child != null && child !== false) node.append(child);
  }
  return node;
}

export function arrow() { return el('span', {class:'arrow', 'aria-hidden':'true'}, '→'); }
export const link = (href, label, css = '', extra = null) => el('a', {href, class:css}, label, extra);
export const action = (href, label, secondary = false) => link(href, label, secondary ? 'button secondary' : 'button', arrow());
export const button = (label, callback, css = 'button') => el('button', {type:'button', class:css, onclick:callback}, label);
export const pending = () => el('div', {class:'skeleton', role:'status'}, t('Загрузка…','Жүктелуде…'));
export const h1 = (title) => el('h1', {class:'page-title'}, title);
export const note = (text, bad = false) => el('p', {class:'notice' + (bad ? ' bad' : ''), role:bad ? 'alert' : 'status'}, text);
export const back = (href, label) => link(href, '←  ' + label, 'back');
export const empty = (title, copy, control = null) => el('div', {class:'empty-state'}, el('h3', {}, title), el('p', {}, copy), control);
export const cleanPath = location.pathname.replace(/\/$/, '') || '/';
export const pathFor = id => '/courses/' + encodeURIComponent(id);
export const lessonPath = (cid, lid) => pathFor(cid) + '/lessons/' + encodeURIComponent(lid);
export const loginPath = target => '/login?next=' + encodeURIComponent(target);
export function safeNext() {
  const target = new URLSearchParams(location.search).get('next');
  if (!target || !/^\/(?:library|profile|catalog|courses\/[\w.-]+(?:\/lessons\/[\w.-]+)?)$/.test(target)) return '/library';
  return target;
}
export const queryNext = () => '?next=' + encodeURIComponent(safeNext());

export async function api(route, method = 'GET', body = undefined) {
  /** @type {RequestInit} */
  const options = {method, credentials:'same-origin', headers:{Accept:'application/json'}};
  if (body !== undefined) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }
  const response = await fetch('/api/' + route, options);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw Object.assign(new Error('request'), {status:response.status, code:data.error});
  }
  return data;
}
export function errorText(error) {
  const code = String(error?.code ?? '').toLowerCase();
  if (/invalid_credentials|invalid_login|login_failed/.test(code)) return t('Проверьте почту и пароль.','Пошта мен құпиясөзді тексеріңіз.');
  if (/email_not_confirmed/.test(code)) return t('Подтвердите почту по ссылке в письме.','Хаттағы сілтеме арқылы поштаңызды растаңыз.');
  if (/weak_password|invalid_password/.test(code)) return t('Выберите более длинный и сложный пароль.','Ұзын әрі күрделі құпиясөз таңдаңыз.');
  if (/already_registered|email_exists|user_already_exists/.test(code)) return t('У этой почты уже есть аккаунт. Попробуйте войти.','Бұл поштаға аккаунт тіркелген. Кіріп көріңіз.');
  if (/invalid_email/.test(code)) return t('Проверьте адрес электронной почты.','Электрондық пошта мекенжайын тексеріңіз.');
  if (error?.status === 401) return t('Пожалуйста, войдите в аккаунт.','Аккаунтыңызға кіріңіз.');
  if (error?.status === 403) return t('Для этого действия нужен доступ к курсу.','Бұл әрекет үшін курсқа қол жеткізу қажет.');
  if (error?.status === 404) return t('Материал пока недоступен.','Материал әзірге қолжетімсіз.');
  if (error?.status === 429) return t('Слишком много запросов. Попробуйте немного позже.','Сұрау саны тым көп. Сәл кейінірек қайталап көріңіз.');
  if (error?.status >= 400 && error.status < 500) return t('Проверьте введённые данные и повторите попытку.','Енгізілген деректерді тексеріп, қайталаңыз.');
  return t('Не удалось загрузить данные. Проверьте соединение и повторите попытку.','Деректер жүктелмеді. Байланысты тексеріп, қайталаңыз.');
}
export function failure(error, retry = null) {
  return el('div', {class:'empty-state'}, note(errorText(error), true), retry && button(t('Повторить','Қайталау'), retry, 'button secondary'));
}
export function safeMedia(value) {
  if (typeof value !== 'string' || !value) return null;
  try {
    const u = new URL(value, location.origin);
    return u.protocol === 'https:' || (u.origin === location.origin && u.protocol === 'http:') ? u.href : null;
  } catch { return null; }
}
export const brand = () => link('/', el('span', {class:'brand-inner'}, el('img', {src:'/assets/mark.png', alt:'', width:42, height:42}), el('span', {}, el('strong', {}, 'ZHANAR'), el('small', {}, 'MASSAGE ACADEMY'))), 'brand');
export function wordCount(number, words) {
  const form = new Intl.PluralRules(language).select(number);
  return new Intl.NumberFormat(language).format(number) + ' ' + (language === 'kk' ? words[3] : words[{one:0,few:1,other:2}[form] ?? 2]);
}
export const lessonsCount = number => wordCount(number, ['урок','урока','уроков','сабақ']);
export function duration(seconds) {
  if (!(seconds > 0)) return '';
  return Math.ceil(seconds / 60) + t(' мин',' мин');
}
