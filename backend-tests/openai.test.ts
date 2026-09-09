import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import OpenAI from 'openai';
import sharp from 'sharp';
import { identify,validateAudioDuration,validateResult } from '../backend/src/server/ai';
import type { Upload } from '../backend/src/server/storage';
function wave(seconds=1) {
  const b=Buffer.alloc(44+16000*seconds*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(16000,24);b.writeUInt32LE(32000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(b.length-44,40);return b;
}
test('the OpenAI SDK sends image identification and transcribed voice through structured Responses',async()=>{
  const requests:{url:string;body:string}[]=[];
  const result={items:[{name:'Eggs',calories:160,portion:'2 eggs',confidence:'medium'}],notes:'Estimated'};
  const server=createServer(async(req,res)=>{
    const chunks:Buffer[]=[];for await(const chunk of req)chunks.push(chunk);
    requests.push({url:req.url!,body:Buffer.concat(chunks).toString()});res.setHeader('content-type','application/json');
    if(req.url==='/v1/audio/transcriptions')res.end(JSON.stringify({text:'I ate two eggs.'}));
    else res.end(JSON.stringify({id:'resp_test',object:'response',status:'completed',created_at:1,model:'test',output:[{id:'msg_test',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:JSON.stringify(result),annotations:[]}]}]}));
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
    await assert.rejects(validateAudioDuration(wave(66),'audio/wav'));
  } finally { await new Promise<void>((resolve,reject)=>server.close(e=>e?reject(e):resolve())); }
});

test('normalizes visual and preparation words from portions',()=>{
  const result = validateResult({items:[{name:'Banana',calories:100,portion:'1 medium banana shown, peeled',confidence:'medium'}],notes:''});
  assert.equal(result.items[0].portion,'1 medium banana');
});
