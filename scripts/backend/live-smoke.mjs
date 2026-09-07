import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import sharp from 'sharp';
import {deepStrictEqual} from 'node:assert';
process.loadEnvFile('.env.development.local');
const base='http://127.0.0.1:3000';
async function post(path,data){const r=await fetch(base+'/api/v1/'+path,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+process.env.DEV_API_TOKEN},body:JSON.stringify({nonce:crypto.randomUUID(),...data})});const b=await r.json();if(!r.ok)throw new Error(path+': '+JSON.stringify(b));return b;}
const report={testedAt:new Date().toISOString(),synthetic:true,results:[]};
for(const [kind,file,mime] of [['image','Artwork/TestFixtures/chicken-rice-broccoli.png','image/jpeg'],['audio','Artwork/TestFixtures/voice-lunch.wav','audio/wav']]){
 let bytes=await readFile(file);if(kind==='image')bytes=await sharp(bytes).resize({width:2048,height:2048,fit:'inside',withoutEnlargement:true}).jpeg({quality:85}).toBuffer();
 const signed=await post('uploads/sign',{kind,mime,byteLength:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
 const r=await fetch(signed.uploadURL,{method:'PUT',headers:{'Content-Type':mime,Authorization:'Bearer '+process.env.DEV_API_TOKEN},body:bytes});if(!r.ok)throw new Error('upload '+r.status);
 const result=await post('food/analyze',{uploadId:signed.uploadId});
 if(!result.items?.length || result.items.some(x=>!Number.isFinite(x.calories)))throw new Error('Invalid result');
 const again=await post('food/analyze',{uploadId:signed.uploadId});deepStrictEqual(result,again);
 report.results.push({kind,bytes:bytes.length,result,retryMatches:true});console.log(kind,result.items.map(x=>x.name+': '+x.calories).join(', '));
 await writeFile('Documentation/Release/live-ai-smoke.json',JSON.stringify(report,null,2));
}
