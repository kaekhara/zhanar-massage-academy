import {action, api, brand, changeLanguage, cleanPath, el, failure, language, link, note, t} from './ui.js';
import {catalog, home} from './catalog.js';
import {coursePage, lessonPage} from './learn.js';
import {authPage, profilePage} from './account.js';

const main = document.getElementById('main');
const header = document.getElementById('header');
const footer = document.getElementById('footer');
const flow = new URLSearchParams(location.search).get('flow');
const navigation = [[t('Главная','Басты бет'),'/'],[t('Каталог','Каталог'),'/catalog'],[t('Мои курсы','Менің курстарым'),'/library']];
function shell(user) {
  const nav = el('nav', {class:'main-nav','aria-label':t('Навигация','Навигация')});
  for (const [label,href] of navigation) {
    const current = cleanPath === href || href === '/catalog' && cleanPath.startsWith('/courses/');
    nav.append(el('a',{href,'aria-current':current?'page':null},label));
  }
  const languages = el('div',{class:'language',role:'group','aria-label':t('Язык сайта','Сайт тілі')},
    ...[['ru','РУ'],['kk','ҚАЗ']].map(([value,label])=>el('button',{type:'button',lang:value,'aria-pressed':language === value ? 'true' : 'false',onclick:()=> { if (language !== value) changeLanguage(value); }},label)));
  header.replaceChildren(el('div',{class:'wrap header-row'},brand(),nav,el('div',{class:'header-actions'},languages,
    action(user ? '/profile' : '/login',user ? t('Кабинет','Кабинет') : t('Войти','Кіру'),true))));
}
footer.replaceChildren(el('div',{class:'wrap footer-row'},brand(),el('nav',{'aria-label':t('Навигация в подвале','Төменгі навигация')},
  link('/catalog',navigation[1][0]),link('/library',navigation[2][0]),link('/help',t('Помощь','Көмек')),link('/privacy',t('Конфиденциальность','Құпиялық')))));
shell(null);

async function render() {
  try {
    if (cleanPath === '/' && !flow) main.replaceChildren(...home());
    const session = await api('session');
    shell(session.user);
    const path = cleanPath;
    let nodes;
    if (path === '/' && flow === 'recovery') nodes = await authPage('password',session,flow);
    else if (path === '/' && flow === 'invalid') nodes = await authPage('recover',session,flow);
    else if (path === '/') {
      if (!flow) return;
      nodes = home();
      if (flow === 'confirmed') nodes.unshift(note(t('Почта подтверждена. Добро пожаловать в академию.','Поштаңыз расталды. Академияға қош келдіңіз.')));
    }
    else if (path === '/catalog' || path === '/library') nodes = await catalog(path === '/library',session.user);
    else if (path === '/profile') nodes = await profilePage(session.user);
    else if (path === '/privacy' || path === '/help') nodes = (await import('./help.js')).helpPage(path === '/privacy',(await api('settings')).links);
    else if (path === '/admin') nodes = await (await import('./admin.js')).admin();
    else if (['/login','/signup','/password','/recover'].includes(path)) nodes = await authPage(path.slice(1),session,flow);
    else {
      const course = /^\/courses\/([^/]+)(?:\/lessons\/([^/]+))?$/.exec(path);
      if (!course) throw Object.assign(new Error('page'),{status:404});
      const cid = decodeURIComponent(course[1]);
      nodes = course[2] ? await lessonPage(cid,decodeURIComponent(course[2]),session.user) : await coursePage(cid,session.user);
    }
    main.replaceChildren(...(Array.isArray(nodes) ? nodes : [nodes]).filter(Boolean));
    const heading = main.querySelector('h1');
    if (heading) document.title = heading.textContent + ' · ZHANAR';
  } catch(e) {
    if (cleanPath === '/' && !flow && main.querySelector('.hero')) {
      header.append(el('div',{class:'wrap'},failure(e,()=>location.reload())));
    } else main.replaceChildren(failure(e,()=>location.reload()));
  }
}
void render();
