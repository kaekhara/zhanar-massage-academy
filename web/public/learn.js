import {action, api, back, button, duration, el, empty, errorText, failure, h1, lessonPath, lessonsCount, localized, loginPath, note, pathFor, pending, safeMedia, t} from './ui.js';

async function progressFor(course, user) {
  if (!user || !course.owned) return new Set();
  const data = await api('progress');
  return new Set(data.completedLessonIDs);
}
function outline(course, done, current = '') {
  const sections = course.sections.map((section, index) => el('section', {class:'module'},
    el('header', {}, el('span', {class:'eyebrow'}, t('Раздел ','Бөлім ') + (index + 1)), el('h3', {}, localized(section,'title'))),
    section.lessons.length ? el('ol', {class:'lessons'}, section.lessons.map(lesson => {
      const status = done.has(lesson.id) ? t('Пройден','Аяқталды') : !course.owned && lesson.isPreview ? t('Открытый урок','Ашық сабақ') : '';
      return el('li', {}, el('a', {href:lessonPath(course.id,lesson.id), 'aria-current':current === lesson.id ? 'page' : null},
        el('span', {class:'lesson-symbol', 'aria-hidden':'true'}, done.has(lesson.id) ? '✓' : '▷'),
        el('span', {}, localized(lesson,'title'), status && el('small', {}, status)), el('span', {class:'time'}, duration(lesson.durationSeconds))));
    })) : el('p', {class:'quiet'}, t('Уроки пока не опубликованы.','Сабақтар әзірге жарияланбаған.'))));
  return el('div', {class:'outline', id:'program'}, el('h2', {}, t('Программа курса','Курс бағдарламасы')), sections.length ? sections :
    el('p', {class:'quiet'}, t('Программа скоро появится здесь.','Бағдарлама жақында осында жарияланады.')));
}
export async function coursePage(id, user) {
  const {course} = await api('courses/' + encodeURIComponent(id));
  const done = await progressFor(course, user);
  const all = course.sections.flatMap(s => s.lessons);
  const first = course.owned ? all.find(item => !done.has(item.id)) || all[0] : all.find(item => item.isPreview);
  const image = safeMedia(course.coverURL);
  const meta = [lessonsCount(course.lessonCount), duration(course.durationSeconds), course.owned ? t('Есть доступ','Қолжетімді') : ''].filter(Boolean);
  const name = localized(course,'title');
  document.title = name + ' · ZHANAR';
  const hero = el('div', {class:'course-intro'}, el('div', {},
    el('p', {class:'eyebrow'}, localized(course,'category')), h1(name),
    localized(course,'subtitle') && el('p', {class:'lead'}, localized(course,'subtitle')), el('p', {class:'meta'}, meta.join(' · ')),
    first ? action(lessonPath(id,first.id), course.owned ? t('Перейти к уроку','Сабаққа өту') : t('Открытый урок','Ашық сабақ')) : null),
    image ? el('img', {src:image, class:'course-image', alt:'', onerror:event => event.currentTarget.hidden = true}) : null);
  const description = localized(course,'description');
  const teacher = course.instructorName ? el('aside', {class:'teacher'}, el('div', {class:'eyebrow'}, t('Преподаватель','Оқытушы')), el('h3',{},course.instructorName),
    localized(course,'instructorTitle') && el('p',{},localized(course,'instructorTitle')), localized(course,'instructorBio') && el('p',{class:'long-text'},localized(course,'instructorBio'))) : null;
  return [back('/catalog',t('Каталог курсов','Курстар каталогы')), hero,
    description && el('section', {class:'copy-block'}, el('h2',{},t('О курсе','Курс туралы')), el('p',{class:'long-text'},description)),
    el('div',{class:'course-layout'},outline(course,done), teacher)];
}

function gated(course, user, target) {
  const title = user ? t('Нужен доступ к курсу','Курсқа қол жеткізу қажет') : t('Войдите для просмотра','Көру үшін кіріңіз');
  const desc = user ? t('Полный курс доступен после покупки в приложении ZHANAR. Используйте тот же аккаунт на сайте.','Толық курс ZHANAR қолданбасында сатып алған соң ашылады. Сайтқа сол аккаунтпен кіріңіз.') :
    t('Используйте почту своего аккаунта ZHANAR.','ZHANAR аккаунтыңыздың поштасын пайдаланыңыз.');
  return empty(title, desc, user ? action(pathFor(course.id),t('Открыть программу','Бағдарламаны ашу'),true) : action(loginPath(target),t('Войти','Кіру')));
}

function player(course, lesson, user) {
  const container = el('div', {class:'player'}, pending());
  const message = el('div', {class:'video-status', 'aria-live':'polite'});
  const group = el('div', {}, container, message);
  async function load() {
    message.replaceChildren();
    container.replaceChildren(pending());
    try {
      const [{url}, resume] = await Promise.all([
        api('lessons/' + encodeURIComponent(lesson.id) + '/video'),
        api('resume').catch(() => null)
      ]);
      const source = safeMedia(url);
      if (!source) throw Object.assign(new Error('video'), {status:404});
      const video = el('video',{controls:true, playsinline:true, preload:'metadata', 'aria-label':localized(lesson,'title')});
      const start = resume?.positions.find(row => row.lessonID === lesson.id)?.positionSeconds || 0;
      if (resume === null) message.replaceChildren(note(t('Не удалось загрузить сохранённую позицию.','Сақталған орынды жүктеу мүмкін болмады.'),true));
      video.addEventListener('loadedmetadata', () => { if (Number.isFinite(video.duration) && start > 0 && start < video.duration - 2) video.currentTime = start; }, {once:true});
      let lastRequested = start;
      let lastTime = Date.now();
      let pendingSave = Promise.resolve();
      let revision = 0;
      const queueSave = (unloading = false) => {
        if (!video.currentSrc || !Number.isFinite(video.currentTime)) return;
        const seconds = video.ended ? 0 : Math.floor(video.currentTime);
        if (seconds === lastRequested) return;
        const stamp = ++revision;
        const body = {lessonID:lesson.id, positionSeconds:seconds, updatedAt:new Date().toISOString()};
        lastRequested = seconds;
        lastTime = Date.now();
        if (unloading) {
          void fetch('/api/resume', {method:'POST', credentials:'same-origin', keepalive:true, headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)}).catch(() => {});
          return;
        }
        pendingSave = pendingSave.then(async () => {
          if (revision !== stamp) return;
          try { await api('resume', 'POST', body); message.replaceChildren(); }
          catch {
            if (stamp === revision) lastRequested = -1;
            message.replaceChildren(note(t('Позиция просмотра пока не сохранена.','Көру орны әзірге сақталмады.'),true));
          }
        });
      };
      video.addEventListener('timeupdate', () => { if (Date.now() - lastTime > 15000) queueSave(); });
      video.addEventListener('pause', () => queueSave());
      video.addEventListener('ended', () => queueSave());
      const pageHide = () => queueSave(true);
      window.addEventListener('pagehide', pageHide, {once:true});
      video.addEventListener('error', () => {
        window.removeEventListener('pagehide', pageHide);
        container.replaceChildren(empty(t('Не удалось воспроизвести видео','Бейне ойнатылмады'), t('Проверьте соединение и попробуйте снова.','Байланысты тексеріп, қайталап көріңіз.'),button(t('Загрузить снова','Қайта жүктеу'),load,'button secondary')));
      }, {once:true});
      container.replaceChildren(video);
      video.src = source;
    } catch (e) {
      container.replaceChildren(e.status === 403 || e.status === 401 ? gated(course,e.status === 401 ? null : user,location.pathname) : failure(e,load));
    }
  }
  void load();
  return group;
}

export async function lessonPage(cid, lid, user) {
  const {course} = await api('courses/' + encodeURIComponent(cid));
  const all = course.sections.flatMap(s => s.lessons);
  const index = all.findIndex(item => item.id === lid);
  if (index < 0) throw Object.assign(new Error('lesson'), {status:404});
  const lesson = all[index];
  const done = await progressFor(course,user);
  const title = localized(lesson,'title');
  document.title = title + ' · ZHANAR';
  const description = localized(lesson,'description');
  const curriculum = el('aside', {class:'syllabus'}, outline(course,done,lid));
  const controls = el('div',{class:'lesson-actions'});
  const status = el('div', {'aria-live':'polite'});
  function buttons() {
    controls.replaceChildren();
    if (course.owned && user) {
      if (done.has(lid)) controls.append(el('span', {class:'completed'}, '✓  ' + t('Урок пройден','Сабақ аяқталды')));
      else {
        const complete = button(t('Отметить как пройденный','Аяқталды деп белгілеу'), async () => {
          complete.disabled = true;
          status.replaceChildren();
          try {
            await api('progress','POST',{lessonID:lid});
            done.add(lid);
            buttons();
            curriculum.replaceChildren(outline(course,done,lid));
            status.replaceChildren(note(t('Прогресс сохранён.','Оқу барысы сақталды.')));
          } catch (e) { complete.disabled = false; status.replaceChildren(note(errorText(e),true)); }
        });
        controls.append(complete);
      }
    }
    if (all[index+1]) controls.append(action(lessonPath(cid,all[index+1].id),t('Следующий урок','Келесі сабақ'),true));
  }
  buttons();
  const main = el('section',{}, el('div',{class:'eyebrow'},t('Урок ','Сабақ ') + (index+1) + ' / ' + all.length),
    h1(title), user && (course.owned || lesson.isPreview) ? player(course,lesson,user) : gated(course,user,location.pathname),
    description && el('p',{class:'long-text'},description), controls, status);
  return [back(pathFor(cid),localized(course,'title')), el('div',{class:'lesson-layout'},main,curriculum)];
}
