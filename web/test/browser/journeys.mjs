/* global document, innerWidth */
// An isolated upstream lets this test exercise the real HTTP server, cookies and UI without school data.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {chromium} from 'playwright-core';
import {makeServer} from '../../server.mjs';

const account={id:'test-student',email:'learner@example.test'};
let name='Ученик';
const drafts=[];
const completed=new Set();
const lesson={id:'test.lesson',title:'Сабақ',title_ru:'Первый урок',duration_seconds:60,is_preview:true};
const course={id:'test.course',store_product_id:'test.course',is_published:true,title:'Сынақ',title_ru:'Тестовый курс',category:'Оқу',category_ru:'Практика',course_sections:[{id:'s',title:'Бөлім',title_ru:'Раздел',lessons:[lesson]}]};
async function upstream(path,{method,body,token}) {
  const url=new URL(path,'https://fixture.invalid');
  switch(url.pathname){
    case '/auth/v1/token': return {user:account,access_token:'test-access',refresh_token:'test-refresh'};
    case '/auth/v1/user': assert.equal(token,'test-access');return account;
    case '/auth/v1/logout':return {};
    case '/rest/v1/course_admins':return [{user_id:account.id}];
    case '/rest/v1/profiles':
      if (method==='GET')return [{display_name:name}];
      if(body.display_name)name=body.display_name;
      return null;
    case '/rest/v1/courses':
      if(method==='POST'){drafts.push({...body,course_sections:[]});return [{id:body.id}];}
      if(method==='DELETE'){
        const index=drafts.findIndex(d=>url.searchParams.get('id')==='eq.'+d.id);
        return index===-1?[]:drafts.splice(index,1);
      }
      return [{...course,verified_purchases:token?[{product_id:'test.course'}]:[]},...(url.searchParams.has('is_published')?[]:drafts)];
    case '/rest/v1/lesson_progress':
      if(method==='POST')completed.add(body.lesson_id);
      return [...completed].map(lesson_id=>({lesson_id}));
    case '/rest/v1/lesson_resume_state':return [];
    case '/rest/v1/lessons':return [{...lesson,course_sections:{courses:{is_published:true,store_product_id:'test.course',verified_purchases:[{product_id:'test.course'}]}}}];
    default:throw Error('Unexpected test request: '+url.pathname);
  }
}
const cfg={origin:'http://127.0.0.1',supabaseURL:'https://fixture.invalid',key:'test',links:{},phoneEnabled:false};
const server=makeServer(cfg,upstream);
server.listen(0,'127.0.0.1');
await once(server,'listening');
cfg.origin+=':'+server.address().port;
let browser;
try {
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  const page=await browser.newPage({viewport:{width:390,height:844},locale:'ru-RU'});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  const visit=route=>page.goto(cfg.origin+route);
  await visit('/');
  await page.getByRole('heading',{name:'Тестовый курс'}).waitFor();
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.getByRole('button',{name:'ҚАЗ'}).click();
  await page.getByRole('heading',{name:'Сынақ'}).waitFor();
  await page.getByRole('button',{name:'РУ'}).click();
  await visit('/catalog');
  await page.getByRole('searchbox').fill('нет совпадений');
  await page.getByRole('button',{name:'Сбросить фильтры'}).click();
  await page.getByRole('heading',{name:'Тестовый курс'}).click();
  await page.getByRole('heading',{name:'Программа курса'}).waitFor();
  await visit('/login');
  await page.getByLabel('Электронная почта').fill(account.email);
  await page.getByLabel('Пароль',{exact:true}).fill('fixture-testing');
  await page.getByRole('button',{name:'Войти',exact:true}).click();
  await page.waitForURL('**/library');
  await visit('/courses/test.course/lessons/test.lesson');
  await page.getByRole('button',{name:'Отметить как пройденный'}).click();
  await page.getByText('Прогресс сохранён.').waitFor();
  await page.reload();
  await page.getByText(/Урок пройден/).waitFor();
  await page.setViewportSize({width:1280,height:800});
  await visit('/profile');
  await page.getByLabel('Имя',{exact:true}).fill('Новое имя');
  await page.getByRole('button',{name:'Сохранить',exact:true}).click();
  await page.getByText('Изменения сохранены.').waitFor();
  await page.reload();
  assert.equal(await page.getByLabel('Имя',{exact:true}).inputValue(),'Новое имя');
  await page.getByRole('link',{name:'Управление академией'}).click();
  await page.getByRole('button',{name:'Создать курс'}).click();
  await page.getByLabel('ID продукта App Store').fill('test.new.course');
  await page.getByLabel('Название · ҚАЗ',{exact:true}).fill('Жаңа курс');
  await page.getByLabel('Название · РУС',{exact:true}).fill('Новый курс');
  await page.getByRole('button',{name:'Сохранить',exact:true}).click();
  const entry=page.locator('.tree details').filter({has:page.getByText('Новый курс',{exact:true})});
  await entry.locator('summary').click();
  await entry.getByRole('button',{name:'Редактировать'}).click();
  page.once('dialog',dialog=>dialog.accept());
  await page.getByRole('button',{name:'Удалить',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('.admin-tools'));
  assert.equal(drafts.length,0);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await visit('/profile');
  await page.getByRole('button',{name:'Выйти из аккаунта'}).click();
  await page.waitForURL(cfg.origin+'/');
  await visit('/library');
  await page.getByRole('heading',{name:'Войдите в свой аккаунт'}).waitFor();
  assert.deepEqual(errors,[]);
  console.log('Browser journeys passed at 390 and 1280 px');
} finally {await browser?.close();server.close();}
