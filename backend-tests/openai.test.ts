import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import OpenAI from 'openai';
import sharp from 'sharp';
import { identify,identifyText,importMealFromImages,importMealFromText,importMealFromWebsite,recipeServingCount,validateAudioDuration,validateResult } from '../backend/src/server/ai';
import { mealImportInput } from '../backend/src/server/api';
import type { Upload } from '../backend/src/server/storage';
function wave(seconds=1) {
  const b=Buffer.alloc(44+16000*seconds*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(16000,24);b.writeUInt32LE(32000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(b.length-44,40);return b;
}
test('the OpenAI SDK sends image identification and transcribed voice through structured Responses',async()=>{
  const requests:{url:string;body:string}[]=[];
  const result={items:[{name:'Eggs',calories:160,portion:'2 eggs',servingSize:'1 egg',servings:2,confidence:'medium',macros:{protein:12,totalCarbs:1,fiber:0,fat:10}}],notes:'Estimated'};
  const server=createServer(async(req,res)=>{
    const chunks:Buffer[]=[];for await(const chunk of req)chunks.push(chunk);
    requests.push({url:req.url!,body:Buffer.concat(chunks).toString()});res.setHeader('content-type','application/json');
    if(req.url==='/v1/audio/transcriptions')res.end(JSON.stringify({text:'I ate two eggs.'}));
    else res.end(JSON.stringify({id:'resp_test',object:'response',status:'completed',created_at:1,model:'test',output:[{id:'msg_test',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:JSON.stringify({...result,mealName:'Egg breakfast'}),annotations:[]}]}]}));
  });
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  const port=(server.address() as {port:number}).port;
  const client=new OpenAI({apiKey:'test-key',baseURL:`http://127.0.0.1:${port}/v1`,maxRetries:0});
  const upload={kind:'image',mime:'image/jpeg'} as Upload;
  try {
    const image=await sharp({create:{width:10,height:10,channels:3,background:'red'}}).jpeg().toBuffer();
    assert.deepEqual(await identify(upload,image,client),result);
    const body=JSON.parse(requests[0].body);
    assert.equal(body.model,'gpt-6-astra');assert.equal(body.store,false);
    assert.ok(body.input[0].content[0].image_url.startsWith('data:image/jpeg;base64,'));
    assert.equal(body.text.format.strict,true);
    const voice=await identify({...upload,kind:'audio',mime:'audio/wav'},wave(),client);
    assert.equal(voice.transcript,'I ate two eggs.');assert.equal(voice.items[0].calories,160);
    assert.equal(requests[1].url,'/v1/audio/transcriptions');assert.ok(requests[1].body.includes('gpt-transcribe'));
    assert.ok(requests[2].body.includes('I ate two eggs.'));
    const imported=await importMealFromWebsite('https://example.com/recipe',false,client);
    assert.equal(imported.mealName,'Egg breakfast');assert.equal(imported.items[0].name,'Eggs');
    // Released apps keep one-serving link imports with no serving count.
    assert.equal(imported.recipeServings,undefined);assert.ok(JSON.parse(requests[3].body).instructions.includes('one practical serving'));
    assert.ok(requests[3].body.includes('web_search'));assert.ok(requests[3].body.includes('https://example.com/recipe'));
    await assert.rejects(importMealFromWebsite('http://example.com/recipe',false,client));
    await assert.rejects(validateAudioDuration(wave(66),'audio/wav'));
  } finally { await new Promise<void>((resolve,reject)=>server.close(e=>e?reject(e):resolve())); }
});

test('spoken text preserves corrected food, portion and macros through the Responses SDK',async()=>{
  let request: any;
  const result={items:[{name:'Navel orange',calories:62,portion:'1 medium orange',servingSize:'1 medium orange',servings:1,confidence:'medium',macros:{protein:1.2,totalCarbs:15.4,fiber:3.1,fat:0.2}}],notes:'Assumed one medium orange.'};
  const client=new OpenAI({apiKey:'test-key',maxRetries:0,fetch:async(_url,init)=>{
    request=JSON.parse(String(init?.body));
    return new Response(JSON.stringify({id:'resp_test',object:'response',status:'completed',created_at:1,model:'test',output:[{id:'msg_test',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:JSON.stringify(result),annotations:[]}]}]}),{headers:{'content-type':'application/json'}});
  }});
  assert.deepEqual(await identifyText('naval orange',client),{...result,transcript:'naval orange'});
  assert.ok(request.input[0].content[0].text.endsWith('naval orange'));
  assert.ok(request.instructions.includes('speech-recognition errors'));
  assert.ok(request.instructions.includes('If the amount is omitted'));
  assert.equal(request.text.format.strict,true);
});

test('normalizes visual and preparation words from portions',()=>{
  const result = validateResult({items:[{name:'Banana',calories:100,portion:'1 medium banana shown, peeled',servingSize:'1 medium banana peeled',servings:1,confidence:'medium'}],notes:''});
  assert.equal(result.items[0].portion,'1 medium banana');
  assert.equal(result.items[0].servingSize,'1 medium banana');
});

test('keeps useful servings and collapses microscopic serving units',()=>{
  const banana = validateResult({items:[{name:'Bananas',calories:210,portion:'2 medium bananas',servingSize:'1 medium banana',servings:2,confidence:'high'}],notes:''}).items[0];
  assert.equal(banana.servingSize,'1 medium banana');assert.equal(banana.servings,2);
  const rice = validateResult({items:[{name:'Rice',calories:300,portion:'1.5 cups cooked rice',servingSize:'1 grain of rice',servings:3000,confidence:'low'}],notes:''}).items[0];
  assert.equal(rice.servingSize,'1.5 cups cooked rice');assert.equal(rice.servings,1);
});

test('whole-recipe imports return every ingredient and the serving count from a link, pasted text, or photos',async()=>{
  const requests:string[]=[];
  const recipe={mealName:'Southwest Chicken Couscous',recipeServings:7,notes:'',items:[{name:'Chicken thighs',calories:1400,portion:'2 lb chicken thighs',servingSize:'1 lb chicken thighs',servings:2,confidence:'medium',macros:{protein:180,totalCarbs:0,fiber:0,fat:72}}]};
  const server=createServer(async(req,res)=>{
    const chunks:Buffer[]=[];for await(const chunk of req)chunks.push(chunk);
    requests.push(Buffer.concat(chunks).toString());res.setHeader('content-type','application/json');
    res.end(JSON.stringify({id:'resp_test',object:'response',status:'completed',created_at:1,model:'test',output:[{id:'msg_test',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:JSON.stringify(recipe),annotations:[]}]}]}));
  });
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  const client=new OpenAI({apiKey:'test-key',baseURL:`http://127.0.0.1:${(server.address() as {port:number}).port}/v1`,maxRetries:0});
  try {
    const link=await importMealFromWebsite('https://example.com/couscous',true,client);
    assert.equal(link.recipeServings,7);assert.equal(link.items[0].calories,1400);
    const linkBody=JSON.parse(requests[0]);
    assert.ok(linkBody.instructions.includes('ENTIRE recipe'));assert.equal(linkBody.text.format.name,'recipe_import');
    assert.ok(linkBody.text.format.schema.required.includes('recipeServings'));
    const text=await importMealFromText('2 lb chicken thighs, 1 cup couscous. Serves 7.',client);
    assert.equal(text.recipeServings,7);
    const textBody=JSON.parse(requests[1]);
    assert.equal(textBody.tools,undefined);assert.ok(textBody.input[0].content[0].text.includes('Serves 7'));
    const page=await sharp({create:{width:10,height:10,channels:3,background:'white'}}).png().toBuffer();
    const photos=await importMealFromImages([page,page],client);
    assert.equal(photos.mealName,'Southwest Chicken Couscous');assert.equal(photos.recipeServings,7);
    const photoContent=JSON.parse(requests[2]).input[0].content;
    assert.equal(photoContent.filter((part:{type:string})=>part.type==='input_image').length,2);
    assert.ok(photoContent.at(-1).text.includes('2 pages'));
    await assert.rejects(importMealFromImages([],client));
    await assert.rejects(importMealFromImages([page,page,page,page,page,page],client));
    assert.equal(requests.length,3);
  } finally { await new Promise<void>((resolve,reject)=>server.close(e=>e?reject(e):resolve())); }
});

test('recipe serving counts are whole numbers from 1 to 100',()=>{
  assert.equal(recipeServingCount(7),7);assert.equal(recipeServingCount(4.6),5);
  assert.equal(recipeServingCount(0),1);assert.equal(recipeServingCount(-3),1);assert.equal(recipeServingCount(Number.NaN),1);
  assert.equal(recipeServingCount('6'),1);assert.equal(recipeServingCount(480),100);
});

test('recipe import requests take exactly one bounded source',()=>{
  const id='6f1c1d2e-7a1b-4c3d-9e8f-0a1b2c3d4e5f';
  assert.deepEqual(mealImportInput.parse({url:'https://example.com/r',nonce:'n'}),{url:'https://example.com/r'});
  assert.deepEqual(mealImportInput.parse({url:'https://example.com/r',wholeRecipe:true}),{url:'https://example.com/r',wholeRecipe:true});
  assert.deepEqual(mealImportInput.parse({text:'  2 cups rice, 1 lb beans. Serves 4.\n'}),{text:'2 cups rice, 1 lb beans. Serves 4.'});
  assert.deepEqual(mealImportInput.parse({uploadIds:[id]}),{uploadIds:[id]});
  assert.throws(()=>mealImportInput.parse({text:'too short'}));
  assert.throws(()=>mealImportInput.parse({text:'x'.repeat(20_001)}));
  assert.throws(()=>mealImportInput.parse({text:'2 cups rice and beans\u0000 for four people'}));
  assert.throws(()=>mealImportInput.parse({uploadIds:[]}));
  assert.throws(()=>mealImportInput.parse({uploadIds:[id,id]}));
  assert.throws(()=>mealImportInput.parse({uploadIds:Array.from({length:6},(_,i)=>id.slice(0,-1)+i)}));
  assert.throws(()=>mealImportInput.parse({}));
});
