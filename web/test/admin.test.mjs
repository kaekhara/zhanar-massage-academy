import {test} from 'node:test';
import assert from 'node:assert/strict';
import {admin} from '../admin.mjs';
const user={id:'editor',accessToken:'test-session'};
function call(path,method,body,handler) {
  return admin({path:'/api/admin/'+path,method,body,user,supabaseURL:'https://test.invalid',key:'public',request:async (route,options)=>{
    assert.equal(options.token,user.accessToken);
    if(route.startsWith('/rest/v1/course_admins?'))return [{user_id:user.id}];
    return handler(route,options);
  }});
}
test('course creation uses product ID as stable ID and always starts as draft',async()=>{
  const result=await call('courses','POST',{title:'Курс',productID:'school.practice'},(route,{body})=>{
    assert.equal(body.is_published,false);assert.equal(body.store_product_id,body.id);return [{id:body.id}];
  });assert.equal(result.id,'school.practice');
});
test('learner cannot access admin mutations',async()=>{
  await assert.rejects(admin({method:'PATCH',path:'/api/admin/courses/demo',body:{title:'Новый'},user,request:async path=>{
    assert.match(path,/course_admins/);return [];
  }}),{status:403});
});
test('refused publication and zero changed rows surface as failures',async()=>{
  await assert.rejects(call('courses/demo/publication','PATCH',{isPublished:true},()=>{throw Object.assign(new Error(),{code:'23514'});}),{status:409});
  await assert.rejects(call('courses/demo','DELETE',{},()=>[]),{status:409});
});
test('upload validation precedes ticket generation and scoping precedes attachment',async()=>{
  await assert.rejects(call('uploads','POST',{assetType:'video',lessonID:'lesson',contentType:'video/mp4',fileExtension:'mp4',fileSize:50000001},()=>assert.fail()),{status:400});
  await assert.rejects(call('uploads/attach','POST',{assetType:'cover',courseID:'course',path:'other/12345678-abcd-abcd-abcd-123456789abc.png'},()=>[{store_product_id:'course'}]),{status:400});
});
