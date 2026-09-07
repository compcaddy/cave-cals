import test from 'node:test';
import assert from 'node:assert/strict';
import { isDevelopmentUser, localDevelopment, readLimited } from '../backend/src/server/config';
import { validateUpload, verifyBytes } from '../backend/src/server/storage';
import { validateResult, prepareImage, validateAudioDuration } from '../backend/src/server/ai';
import { allowedTransaction } from '../backend/src/server/apple';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
const env = process.env as Record<string,string|undefined>;
test('developer token is rejected in production, on Vercel, remotely, and cross-origin', () => {
  const before = { ...process.env }; const token='x'.repeat(40);
  try {
    env.DEV_API_TOKEN=token;env.NODE_ENV='development';delete env.VERCEL;
    const req=(url='http://127.0.0.1:3000/api/v1/account/status',origin?:string)=>new Request(url,{headers:{authorization:`Bearer ${token}`,...(origin?{origin}:{})}});
    assert.equal(isDevelopmentUser(req()),true);
    assert.equal(isDevelopmentUser(req('http://127.0.0.1:3000/api/v1/account/status','https://evil.example')),false);
    assert.equal(isDevelopmentUser(req('https://example.com')),false);
    env.NODE_ENV='production';assert.equal(isDevelopmentUser(req()),false);
    env.NODE_ENV='development';env.VERCEL='1';assert.equal(isDevelopmentUser(req()),false);
    delete env.VERCEL;assert.equal(isDevelopmentUser(new Request('http://localhost:3000')),false);
  } finally { for(const key of Object.keys(process.env)) if(!(key in before)) delete env[key];Object.assign(env,before); }
});
test('large requests are rejected without trusting Content-Length',async()=>{
  await assert.rejects(readLimited(new Request('http://localhost',{method:'POST',body:'x'.repeat(65)}),64), /too large/);
});
test('upload type, size, and content hash are enforced',()=>{
  const valid={kind:'image' as const,mime:'image/jpeg',byteLength:100,sha256:'0'.repeat(64)};
  assert.doesNotThrow(()=>validateUpload(valid));
  assert.throws(()=>validateUpload({...valid,mime:'image/svg+xml'}));
  assert.throws(()=>validateUpload({...valid,byteLength:21*1024*1024}));
  assert.throws(()=>validateUpload({...valid,kind:'audio',mime:'audio/mp4',byteLength:5*1024*1024}));
  const bytes=Buffer.from('image');const sha256=createHash('sha256').update(bytes).digest('hex');
  assert.doesNotThrow(()=>verifyBytes({byteLength:bytes.length,sha256},bytes));
  assert.throws(()=>verifyBytes({byteLength:bytes.length,sha256},Buffer.from('other')));
});
test('images are decoded, resized, and stripped of metadata; disguised files are rejected',async()=>{
  const input=await sharp({create:{width:4000,height:2500,channels:3,background:'#ff0000'}}).png().toBuffer();
  const output=await prepareImage(input); const meta=await sharp(output).metadata();
  assert.equal(meta.width,2048);assert.equal(meta.format,'jpeg');assert.equal(meta.exif,undefined);
  await assert.rejects(prepareImage(Buffer.from('<svg/>')));
});
test('invalid food output cannot be logged as a successful estimate',()=>{
  const base={items:[{name:'Egg',calories:80,portion:'1 large egg',confidence:'medium'}],notes:''};
  assert.equal(validateResult(base).items.length,1);
  assert.throws(()=>validateResult({...base,items:[{...base.items[0],calories:-1}]}));
  assert.throws(()=>validateResult({...base,items:[{...base.items[0],calories:100001}]}));
  assert.throws(()=>validateResult({...base,items:[{...base.items[0],name:''}]}));
  assert.throws(()=>validateResult({...base,items:Array(21).fill(base.items[0])}));
  assert.deepEqual(validateResult({items:[],notes:'No food visible'}).items,[]);
});
test('audio must have readable duration and be within the recording limit',async()=>{
  await assert.rejects(validateAudioDuration(Buffer.from('not audio'),'audio/mp4'));
  await assert.rejects(validateAudioDuration(Buffer.from('0000ftypfake'),'audio/mp4'));
});
test('wrong products, bundles, family shares, revocations, and non-subscriptions cannot grant paid access',()=>{
  const original=env.APPLE_PRODUCT_IDS;env.APPLE_PRODUCT_IDS='test.monthly';
  const valid={productId:'test.monthly',originalTransactionId:'123',bundleId:'com.philstarkovich.cavecals',type:'Auto-Renewable Subscription',inAppOwnershipType:'PURCHASED'};
  try {
    assert.equal(allowedTransaction(valid),true);
    for(const change of [{productId:'other'},{bundleId:'other'},{revocationDate:1},{inAppOwnershipType:'FAMILY_SHARED'},{type:'Consumable'}]) assert.equal(allowedTransaction({...valid,...change}),false);
  } finally { if(original===undefined)delete env.APPLE_PRODUCT_IDS;else env.APPLE_PRODUCT_IDS=original; }
});

test('sandbox support still rejects forged purchases and notifications', async () => {
  const before = { ...process.env };
  const { appleEnvironments, decodePurchase, verifyNotification } = await import('../backend/src/server/apple');
  try {
    env.APPLE_ENVIRONMENT='Production';env.APPLE_APP_ID='6809208501';env.VERCEL_ENV='production';delete env.APPLE_ALLOW_SANDBOX;
    assert.deepEqual(appleEnvironments(), ['Production']);
    env.APPLE_ALLOW_SANDBOX='true';assert.deepEqual(appleEnvironments(), ['Production','Sandbox']);
    const forged = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from('{"environment":"Sandbox","bundleId":"com.philstarkovich.cavecals"}').toString('base64url')}.fake`;
    await assert.rejects(decodePurchase(forged), /could not verify/);
    await assert.rejects(verifyNotification(forged), /could not verify/);
    env.APPLE_ENVIRONMENT='Sandbox';assert.throws(appleEnvironments, /production purchases first/);
  } finally { for(const key of Object.keys(env)) if(!(key in before)) delete env[key];Object.assign(env,before); }
});
