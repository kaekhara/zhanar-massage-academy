import {action, api, arrow, button, duration, el, empty, failure, h1, language, lessonsCount, link, localized, loginPath, pathFor, pending, safeMedia, t} from './ui.js';

async function publicCatalog(){
  const cacheKey = 'zhanar-public-catalog-v1';
  try {
    const {courses} = await api('courses');
    try {localStorage.setItem(cacheKey,JSON.stringify(courses.map(c=>({...c,owned:false}))));}
    catch { /* Storage is optional on shared and private devices. */ }
    return {courses,cached:false};
  } catch(error) {
    if (error.status && error.status < 500) throw error;
    let courses;
    try {courses=JSON.parse(localStorage.getItem(cacheKey));} catch { /* No readable copy. */ }
    if (!Array.isArray(courses) || !courses.length) throw error;
    return {courses,cached:true};
  }
}
const offlineNotice = () => el('p',{class:'notice',role:'status'},t('Показан последний сохранённый каталог.','Соңғы сақталған каталог көрсетілген.'), ' ',button(t('Обновить','Жаңарту'),()=>location.reload(),'text-link'));

const catalogLabel = () => t('Каталог курсов','Курстар каталогы');
const categoryLabel = c => localized(c, 'category');
function cover(course) {
  const url = safeMedia(course.coverURL);
  const frame = el('div', {class:'card-cover'});
  const fallback = () => frame.replaceChildren(el('img', {class:'cover-mark', src:'/assets/mark.png', alt:'', width:84, height:84}));
  if (url) frame.append(el('img', {src:url, alt:'', loading:'lazy', onerror:fallback}));
  else fallback();
  return frame;
}
function card(course) {
  const title = localized(course, 'title');
  const meta = [lessonsCount(course.lessonCount), duration(course.durationSeconds)].filter(Boolean);
  return link(pathFor(course.id), el('article', {class:'course-card'}, cover(course),
    el('div', {class:'card-content'}, categoryLabel(course) && el('div', {class:'eyebrow'}, categoryLabel(course)),
      el('h3', {}, title), localized(course,'subtitle') && el('p', {}, localized(course,'subtitle')),
      el('div', {class:'card-bottom'}, el('span', {}, meta.join(' · ')), arrow()))), 'card-link');
}

export function home() {
  const showcase = el('section', {class:'showcase', id:'courses'},
    el('div', {class:'section-head'}, el('h2', {}, t('Курсы академии','Академия курстары')), link('/catalog', t('Весь каталог','Барлық курстар'), 'text-link', arrow())));
  const list = el('div', {}, pending());
  showcase.append(list);
  async function load() {
    list.replaceChildren(pending());
    try {
      const {courses,cached} = await publicCatalog();
      list.replaceChildren(courses.length ? el('div', {class:'card-grid'}, courses.slice(0,3).map(card)) :
        empty(t('Готовим новые курсы','Жаңа курстар дайындалуда'), t('Здесь появятся программы, когда академия откроет к ним доступ.','Академия бағдарламаларды жариялаған кезде олар осы жерде пайда болады.')));
      if (cached) list.prepend(offlineNotice());
    } catch (e) { list.replaceChildren(failure(e, load)); }
  }
  void load();
  return [
    el('section', {class:'hero'},
      el('div', {class:'hero-copy'},
        el('div', {class:'eyebrow hero-label'}, el('i', {'aria-hidden':'true'}), t('Онлайн-академия','Онлайн академия')),
        el('h1', {}, t('Школа','Массаж'), el('em', {}, t('массажа','мектебі'))),
        el('p', {class:'lead'}, t('Изучайте массаж по видеоурокам Жанар Иманбаевны. Возвращайтесь к практике в своём темпе.','Жанар Иманбаевнаның бейнесабақтарымен массажды үйреніңіз. Жаттығуға өзіңізге ыңғайлы уақытта оралыңыз.')),
        action('/catalog', t('Выбрать курс','Курс таңдау'))),
      el('div', {class:'hero-art'}, el('img', {src:'/assets/studio.webp', alt:t('Практическое занятие по массажу плеча','Иық массажы бойынша тәжірибелік сабақ'), fetchpriority:'high', width:1000, height:750}))),
    showcase,
    el('section', {class:'questions'}, el('h2', {}, t('Об обучении','Оқу туралы')),
      el('div', {class:'answers'}, qa(t('Как устроено обучение?','Оқу қалай өтеді?'), t('Откройте программу курса и выберите урок. Видео можно поставить на паузу, а изученный урок — отметить в программе.','Курс бағдарламасын ашып, сабақты таңдаңыз. Бейнені кідіртіп, өткен сабақты бағдарламада белгілей аласыз.')),
        qa(t('Где найти мои курсы?','Курстарымды қайдан табамын?'), t('Войдите с той же почтой, что и в приложении ZHANAR. Курсы с доступом появятся в разделе «Мои курсы».','ZHANAR қолданбасында пайдаланған поштаңызбен кіріңіз. Қолжетімді курстар «Менің курстарым» бөлімінде көрсетіледі.')),
        qa(t('На каком языке материалы?','Материалдар қай тілде?'), t('Интерфейс доступен на русском и казахском. Содержание и язык уроков зависят от программы курса.','Интерфейс қазақ және орыс тілдерінде қолжетімді. Сабақтың мазмұны мен тілі курс бағдарламасына байланысты.'))))
  ];
}

function qa(question, answer) {
  return el('details', {}, el('summary', {}, question), el('p', {}, answer));
}
export async function catalog(library, user) {
  const title = library ? t('Мои курсы','Менің курстарым') : catalogLabel();
  const header = el('div', {class:'page-head'}, h1(title));
  if (library && !user) return [header, empty(t('Войдите в свой аккаунт','Аккаунтыңызға кіріңіз'), t('Здесь хранятся ваши курсы и прогресс обучения.','Мұнда курстарыңыз бен оқу барысыңыз сақталады.'), action(loginPath('/library'), t('Войти','Кіру')))];
  const {courses,cached} = library ? await api('library') : await publicCatalog();
  if (cached) header.append(offlineNotice());
  if (!courses.length) return [header, library ?
    empty(t('Пока нет курсов','Әзірге курс жоқ'), t('После получения доступа курс появится здесь.','Қолжетімділік берілген соң курс осы жерде пайда болады.'), action('/catalog',catalogLabel())) :
    empty(t('Готовим новые курсы','Жаңа курстар дайындалуда'), t('Опубликованные программы появятся здесь.','Жарияланған бағдарламалар осы жерде көрсетіледі.'))];
  const params = new URLSearchParams(location.search);
  const input = el('input', {type:'search', placeholder:t('Название или преподаватель','Атауы немесе оқытушысы'), 'aria-label':t('Поиск курсов','Курс іздеу'), value:params.get('q') || ''});
  const select = el('select', {'aria-label':t('Направление','Бағыты')}, el('option', {value:''}, t('Все направления','Барлық бағыттар')));
  const categories = [...new Set(courses.map(categoryLabel).filter(Boolean))].sort((a,b) => a.localeCompare(b,language));
  categories.forEach(name => select.append(el('option',{value:name},name)));
  if (categories.includes(params.get('category'))) select.value = params.get('category');
  const grid = el('div', {class:'card-grid'});
  const results = el('p', {class:'result-count', role:'status'});
  const filters = el('div', {class:'filters'}, el('label', {class:'search-field'}, el('span', {class:'search-icon','aria-hidden':'true'}), input), categories.length > 0 && select);
  function refresh() {
    const query = input.value.trim().toLocaleLowerCase(language);
    const matches = courses.filter(c => (!select.value || categoryLabel(c) === select.value) &&
      [localized(c,'title'), localized(c,'subtitle'), categoryLabel(c), c.instructorName].filter(Boolean).join(' ').toLocaleLowerCase(language).includes(query));
    const next = new URLSearchParams();
    if (input.value) next.set('q', input.value);
    if (select.value) next.set('category', select.value);
    history.replaceState(null, '', location.pathname + (next.size ? '?' + next : ''));
    results.textContent = t('Найдено курсов: ','Табылған курс саны: ') + matches.length;
    if (matches.length) grid.replaceChildren(...matches.map(card));
    else grid.replaceChildren(empty(t('Курсы не найдены','Курстар табылмады'), t('Измените поиск или направление.','Іздеу сөзін немесе бағытты өзгертіңіз.'), button(t('Сбросить фильтры','Сүзгілерді тазарту'), () => { input.value = ''; select.value = ''; refresh(); input.focus(); }, 'button secondary')));
  }
  input.addEventListener('input', refresh);
  select.addEventListener('change', refresh);
  refresh();
  return [header, filters, results, grid];
}
