import {action, api, button, el, empty, errorText, h1, link, loginPath, note, queryNext, safeNext, t} from './ui.js';

export const field = (title, options) => el('label', {class:'field'}, el('span',{},title), el('input',options));
const texts = () => ({
  login: [t('Вход','Кіру'), t('Войти','Кіру')],
  signup:[t('Создать аккаунт','Аккаунт ашу'), t('Зарегистрироваться','Тіркелу')],
  recover:[t('Восстановить доступ','Қолжетімділікті қалпына келтіру'), t('Отправить ссылку','Сілтеме жіберу')],
  password:[t('Новый пароль','Жаңа құпиясөз'), t('Сохранить пароль','Құпиясөзді сақтау')]
});

export async function authPage(kind, session, flow) {
  const {user,phoneEnabled} = session;
  const pairs = texts();
  const title = pairs[kind][0];
  const submit = el('button',{type:'submit',class:'button'},pairs[kind][1]);
  const email = field(t('Электронная почта','Электрондық пошта'), {name:'email',type:'email',autocomplete:'email',required:true,maxlength:254});
  const pwd = field(kind === 'password' ? title : t('Пароль','Құпиясөз'), {name:'password',type:'password',autocomplete:kind === 'login' ? 'current-password' : 'new-password',minlength:kind === 'login' ? 1 : 8,maxlength:1024,required:true});
  const display = field(t('Имя','Аты'),{name:'displayName',autocomplete:'name',maxlength:100,required:true});
  const form = el('form',{class:'form stack'});
  const feedback = el('div',{'aria-live':'polite'});
  const wrap = el('section',{class:'form-panel'},h1(title));
  const query = queryNext();
  const swap = (text, href, label) => el('p',{class:'switch-prompt'},text + ' ', link(href,label,'inline-link'));
  if (flow === 'invalid') wrap.append(note(t('Ссылка недействительна или устарела. Запросите новую и откройте её в этом браузере.','Сілтеме жарамсыз немесе мерзімі өткен. Жаңасын сұратып, осы браузерде ашыңыз.'),true));
  if (kind === 'password' && !user) return [wrap, empty(t('Нужна новая ссылка','Жаңа сілтеме қажет'), t('Запросите письмо для восстановления доступа и откройте его в этом браузере.','Қолжетімділікті қалпына келтіру хатын сұратып, осы браузерде ашыңыз.'),action('/recover',pairs.recover[0]))];
  if (kind === 'signup') form.append(display);
  if (kind !== 'password') form.append(email);
  if (kind !== 'recover') form.append(pwd);
  if (kind === 'signup' || kind === 'password') form.append(el('small',{class:'field-hint'},t('Не менее 8 символов.','Кемінде 8 таңба.')));
  if (kind === 'recover') wrap.append(el('p',{class:'quiet'},t('Отправим на вашу почту ссылку для смены пароля. Откройте её в этом браузере.','Поштаңызға құпиясөзді өзгерту сілтемесін жібереміз. Оны осы браузерде ашыңыз.')));
  if (kind === 'login') form.append(link('/recover', t('Забыли пароль?','Құпиясөзді ұмыттыңыз ба?'),'inline-link'));
  form.append(submit);
  wrap.append(form,feedback);
  if (kind === 'login') {
    if (phoneEnabled) {
      const {phoneAccess} = await import('./account-extra.js');
      wrap.append(phoneAccess(safeNext()));
    }
    wrap.append(swap(t('Впервые в академии?','Академияға алғаш келдіңіз бе?'),'/signup' + query,pairs.signup[0]));
  }
  if (kind === 'signup') wrap.append(swap(t('Уже есть аккаунт?','Аккаунтыңыз бар ма?'),'/login'+query,pairs.login[1]));
  if (kind === 'recover') wrap.append(link('/login'+query,t('Вернуться ко входу','Кіруге оралу'),'inline-link'));
  form.addEventListener('submit',async event => {
    event.preventDefault();
    if (submit.disabled) return;
    submit.disabled = true;
    feedback.replaceChildren();
    try {
      const values = Object.fromEntries(new FormData(form));
      const data = await api('auth/'+kind,'POST',values);
      if (kind === 'recover' || (kind === 'signup' && data.confirmationRequired)) {
        form.hidden = true;
        feedback.replaceChildren(note(kind === 'signup' ? t('Проверьте почту. Для подтверждения аккаунта откройте ссылку из письма в этом браузере.','Поштаңызды тексеріңіз. Аккаунтты растау үшін хаттағы сілтемені осы браузерде ашыңыз.') : t('Если аккаунт с такой почтой существует, вам придёт письмо со ссылкой.','Осы поштаға аккаунт тіркелсе, сізге сілтемесі бар хат келеді.')));
        return;
      }
      if (kind === 'password') location.replace('/profile?updated=password');
      else location.assign(safeNext());
    } catch(e) {
      const msg = kind === 'login' && ['upstream_error','authentication_failed'].includes(e.code) && [400,401,403].includes(e.status) ? t('Проверьте почту, пароль и подтверждение аккаунта.','Поштаңызды, құпиясөзіңізді және аккаунттың расталғанын тексеріңіз.') : errorText(e);
      feedback.replaceChildren(note(msg,true));
    } finally { submit.disabled = false; }
  });
  return [el('div',{class:'account-layout'},wrap)];
}

export async function profilePage(user) {
  if (!user) return [h1(t('Личный кабинет','Жеке кабинет')),empty(t('Войдите в аккаунт','Аккаунтқа кіріңіз'),t('Здесь вы можете изменить имя и управлять аккаунтом.','Мұнда атыңызды өзгертіп, аккаунтыңызды басқара аласыз.'), action(loginPath('/profile'),t('Войти','Кіру')))];
  const [profile,admin] = await Promise.all([api('profile'),api('admin/status')]);
  const title = h1(t('Личный кабинет','Жеке кабинет'));
  const input = field(t('Имя','Аты'),{name:'displayName',autocomplete:'name',value:profile.displayName || '',maxlength:100,required:true});
  const save = el('button',{type:'submit',class:'button'},t('Сохранить','Сақтау'));
  const form = el('form',{class:'stack'},input,save);
  const feedback = el('div',{'aria-live':'polite'});
  if (new URLSearchParams(location.search).get('updated') === 'password') feedback.append(note(t('Пароль обновлён.','Құпиясөз жаңартылды.')));
  form.addEventListener('submit',async e => {
    e.preventDefault();
    if (save.disabled) return;
    save.disabled = true;
    feedback.replaceChildren();
    try {
      const updated = await api('profile','PATCH',{displayName:new FormData(form).get('displayName')});
      input.querySelector('input').value = updated.displayName;
      feedback.replaceChildren(note(t('Изменения сохранены.','Өзгерістер сақталды.')));
    } catch(e) { feedback.replaceChildren(note(errorText(e),true)); }
    finally { save.disabled = false; }
  });
  const logout = button(t('Выйти из аккаунта','Аккаунттан шығу'),async () => {
    if (logout.disabled) return;
    logout.disabled = true;
    try { await api('auth/logout','POST',{}); location.replace('/'); }
    catch(e) { feedback.replaceChildren(note(errorText(e),true)); logout.disabled = false; }
  }, 'button secondary');
  const {deleteAccess} = await import('./account-extra.js');
  return [el('div',{class:'page-head'},title), el('div',{class:'profile-layout'},
    el('section',{class:'form-panel'},el('h2',{},t('Личные данные','Жеке деректер')),
      el('p',{class:'quiet'},user.email || user.phone || ''),form,feedback),
    el('aside',{class:'account-options'},el('h2',{},t('Аккаунт','Аккаунт')),action('/library',t('Мои курсы','Менің курстарым'),true),
      admin.isAdmin && action('/admin', t('Управление академией','Академияны басқару'),true),
      user.email && action('/password',t('Изменить пароль','Құпиясөзді өзгерту'),true),logout,deleteAccess()))];
}
