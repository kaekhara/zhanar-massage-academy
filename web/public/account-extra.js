import {api, button, el, errorText, note, t} from './ui.js';

export function phoneAccess(next) {
  const phone = el('input',{name:'phone',type:'tel',autocomplete:'tel',required:true,placeholder:'+7 700 000 00 00'});
  const code = el('input',{name:'code',inputmode:'numeric',pattern:'[0-9]{6}',autocomplete:'one-time-code',required:true,maxlength:6});
  const submit = el('button',{type:'submit',class:'button'},t('Получить код','Код алу'));
  const status = el('div',{'aria-live':'polite'});
  const form = el('form',{class:'stack'},el('label',{class:'field'},t('Телефон','Телефон'),phone),submit,status);
  form.onsubmit = async event => {
    event.preventDefault();
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      if (code.isConnected) {
        await api('auth/verify-phone','POST',{phone:phone.value,code:code.value});
        location.assign(next);
      } else {
        await api('auth/phone','POST',{phone:phone.value});
        phone.readOnly = true;
        form.insertBefore(el('label',{class:'field'},t('Код из SMS','SMS коды'),code),submit);
        submit.textContent = t('Войти','Кіру');
        code.focus();
        status.replaceChildren(note(t('Код отправлен.','Код жіберілді.')));
      }
    } catch (e) { status.replaceChildren(note(errorText(e),true)); }
    finally {submit.disabled = false;}
  };
  return el('details',{},el('summary',{},t('Войти по телефону','Телефон арқылы кіру')),form);
}

export function deleteAccess() {
  const status = el('div',{'aria-live':'polite'});
  const title = t('Удалить аккаунт','Аккаунтты жою');
  const warning = t('Будут удалены профиль и прогресс на всех устройствах. Перенос покупок на новый аккаунт недоступен. Продолжить?', 'Барлық құрылғылардағы профиль мен оқу барысы жойылады. Сатып алуларды жаңа аккаунтқа көшіру мүмкін емес. Жалғастыру керек пе?');
  const control = button(title,async () => {
    if (!confirm(warning)) return;
    control.disabled = true;
    try {await api('auth/delete','POST',{confirm:true}); location.replace('/');}
    catch (e) {status.replaceChildren(note(errorText(e),true)); control.disabled = false;}
  },'button danger');
  return el('div',{},control,status);
}
