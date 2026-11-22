import {api, button, el, errorText, h1, localized, note, t} from './ui.js';

const label = {
  title:t('Название','Атауы'),subtitle:t('Подзаголовок','Қосымша атауы'),description:t('Описание','Сипаттама'),
  category:t('Направление','Бағыты'),instructorName:t('Имя преподавателя','Оқытушының аты'),
  instructorTitle:t('Должность','Лауазымы'),instructorBio:t('Об авторе','Автор туралы'),
  productID:t('ID продукта App Store','App Store өнімінің ID'), sortOrder:t('Порядок','Реті'),
  durationSeconds:t('Длительность в секундах','Ұзақтығы (секунд)'),isPreview:t('Открытый урок','Ашық сабақ')
};
const names = {courses:t('Курс','Курс'),sections:t('Раздел','Бөлім'),lessons:t('Урок','Сабақ')};
const saveText = t('Сохранить','Сақтау');
const mime = {jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',webp:'image/webp',mp4:'video/mp4',mov:'video/quicktime',m4v:'video/x-m4v'};

export async function admin() {
  const {courses} = await api('admin/courses');
  const pane = el('div',{class:'admin-pane'});
  const list = el('div',{class:'tree'});
  const status = el('div',{'aria-live':'polite'});
  function edit(kind,row,endpoint,creating=false) {
    status.replaceChildren();
    const form = el('form',{class:'form-panel stack'});
    pane.replaceChildren(form);
    const title = creating ? t('Создать','Құру') + ' · ' + names[kind] : localized(row,'title');
    form.append(el('h2',{},title));
    const bilingual = kind === 'courses' ? ['title','subtitle','description','category','instructorTitle','instructorBio'] : ['title','description'];
    const keys = [...(kind==='courses' && creating ? ['productID'] : []),...bilingual.flatMap(key=>[key,key+'Ru']),...(kind==='courses'?['instructorName']:[]),'sortOrder',...(kind==='lessons'?['durationSeconds','isPreview']:[])];
    for (const key of keys) {
      const base = key.replace(/Ru$/,'');
      const name = label[base] + (bilingual.includes(base) ? key === base ? ' · ҚАЗ' : ' · РУС' : '');
      const numeric = ['sortOrder','durationSeconds'].includes(key);
      const area = ['description','instructorBio'].includes(base);
      const input = el(area?'textarea':'input',{name:key,required:key==='title'||key==='productID',type:area?null:numeric?'number':key==='isPreview'?'checkbox':'text',min:numeric?0:null});
      if(key==='isPreview' && input instanceof HTMLInputElement) input.checked=!!row[key];
      else input.value=row[key] ?? '';
      form.append(el('label',{class:'field'},name,input));
    }
    const save = el('button',{class:'button',type:'submit'},saveText);
    form.append(save);
    form.onsubmit = async e=>{
      e.preventDefault();
      /** @type {Record<string, string | File | number | boolean>} */
      const body = Object.fromEntries(new FormData(form));
      if(kind==='lessons') {body.isPreview=form.querySelector('input:checked') !== null;body.durationSeconds=body.durationSeconds===''?null:Number(body.durationSeconds);}
      if(body.sortOrder==='') delete body.sortOrder;
      else body.sortOrder=Number(body.sortOrder);
      await run(save,()=>api(endpoint,creating?'POST':'PATCH',body));
    };
    if(!creating) {
      const tools = el('section',{class:'admin-tools stack'});
      pane.append(tools);
      if(kind==='courses') {
        const publish=button(row.isPublished?t('Снять с публикации','Жариялауды тоқтату'):t('Опубликовать курс','Курсты жариялау'),()=>{
          if(confirm(publish.textContent+'?')) void run(publish,()=>api(endpoint+'/publication','PATCH',{isPublished:!row.isPublished}));
        },'button secondary');
        tools.append(publish);
      }
      if(kind!=='sections') {
        const cover=kind==='courses';
        const picker=el('input',{type:'file',accept:cover?'.png,.jpg,.jpeg,.webp':'.mp4,.m4v,.mov'});
        const info = cover ? t('Обложка до 5 МБ','Мұқаба 5 МБ дейін') : t('Видео до 50 МБ','Бейне 50 МБ дейін');
        tools.append(el('label',{class:'field'},info,picker));
        const upload=button(t('Загрузить файл','Файл жүктеу'),async ()=>{
          const file=picker.files[0];
          if(!file || file.size>(cover?5000000:50000000) || !file.size){status.replaceChildren(note(info,true));return;}
          const ext=file.name.split('.').pop().toLowerCase();
          const target={assetType:cover?'cover':'video',[cover?'courseID':'lessonID']:row.id};
          await run(upload,async ()=>{
            const ticket=await api('admin/uploads','POST',{...target,fileSize:file.size,fileExtension:ext,contentType:mime[ext]});
            const result=await fetch(ticket.uploadURL,{method:'PUT',credentials:'omit',redirect:'error',body:file,headers:{'Content-Type':mime[ext],apikey:ticket.apiKey}});
            if(!result.ok) throw new Error('upload');
            await api('admin/uploads/attach','POST',{...target,path:ticket.path});
          });
        },'button secondary');
        tools.append(upload);
      }
      if(kind!=='courses' || (!row.isPublished && !row.sections.length && !row.coverPath)) {
        const remove=button(t('Удалить','Жою'),()=>{
          if(confirm(t('Удалить этот материал вместе с вложенным содержимым?','Осы материалды ішкі мазмұнымен бірге жою керек пе?'))) void run(remove,()=>api(endpoint,'DELETE',{}));
        },'button danger');
        tools.append(remove);
      }
    }
  }
  async function run(control,operation) {
    if(control.disabled)return;
    control.disabled=true;
    status.replaceChildren(note(t('Сохранение…','Сақталуда…')));
    try {await operation();location.reload();}
    catch(e){status.replaceChildren(note(e.code==='course_requirements'?t('Проверьте переводы, уроки и файлы перед публикацией.','Жарияламас бұрын аудармаларды, сабақтар мен файлдарды тексеріңіз.'):errorText(e),true));control.disabled=false;}
  }
  function branch(kind,row) {
    const path='admin/'+kind+'/'+encodeURIComponent(row.id);
    const entry=el('details',{},el('summary',{},localized(row,'title')));
    entry.append(button(t('Редактировать','Өңдеу'),()=>edit(kind,row,path),'text-link'));
    if(kind!=='lessons'){
      const children=kind==='courses'?'sections':'lessons';
      for(const child of row[children]) entry.append(branch(children,child));
      entry.append(button('+ '+names[children],()=>edit(children,{},path+'/'+children,true),'text-link'));
    }
    return entry;
  }
  list.append(button(t('Создать курс','Курс құру'),()=>edit('courses',{},'admin/courses',true)),...courses.map(c=>branch('courses',c)));
  pane.append(note(t('Выберите материал или создайте курс.','Материалды таңдаңыз немесе курс құрыңыз.')));
  return [h1(t('Управление академией','Академияны басқару')),status,el('div',{class:'admin-layout'},list,pane)];
}
