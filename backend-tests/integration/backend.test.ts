import test,{after,before} from 'node:test';
import assert from 'node:assert/strict';
import nextEnv from '@next/env';
import { randomUUID,createHash,generateKeyPairSync,sign } from 'node:crypto';
import { mkdir,writeFile } from 'node:fs/promises';
import path from 'node:path';
import cbor from 'cbor';
import { eq,like,inArray } from 'drizzle-orm';
import { database,closeDatabase } from '../../backend/src/server/db';
import { accounts,devices,uploads,limits,challenges } from '../../backend/src/server/schema';
import { authenticate,challenge } from '../../backend/src/server/auth';
import { consume,tomorrow } from '../../backend/src/server/rate-limit';
import { requirePaid } from '../../backend/src/server/apple';
import { api } from '../../backend/src/server/api';
import { analyze } from '../../backend/src/server/analysis';
import { localPath,deleteUpload,localUpload } from '../../backend/src/server/storage';
nextEnv.loadEnvConfig(process.cwd(),true);
const env=process.env as Record<string,string|undefined>;
const prefix=`test-${randomUUID()}`;const ids:string[]=[];const uploadIds:string[]=[];
const devToken=process.env.DEV_API_TOKEN!;
before(()=>{
  // Refuse to mutate any database other than the explicitly configured development branch.
  assert.equal(process.env.NEON_TEST_BRANCH,'backend-dev','Set NEON_TEST_BRANCH=backend-dev in .env.development.local.');
  assert.ok(process.env.DATABASE_URL?.includes('ep-lingering-unit-axuq6fwj'),'Refusing to test against a different database.');
  env.NODE_ENV='development';delete env.VERCEL;env.OPENAI_API_KEY='test-provider-is-injected';env.APPLE_TEAM_ID='TESTTEAM01';
});
after(async()=>{
  const db=database();
  for(const id of uploadIds){const [u]=await db.select().from(uploads).where(eq(uploads.id,id));if(u)await deleteUpload(u);}
  if(uploadIds.length)await db.delete(uploads).where(inArray(uploads.id,uploadIds));
  await db.delete(challenges).where(like(challenges.keyId,`${prefix}%`));
  if(ids.length){await db.delete(devices).where(inArray(devices.accountId,ids));await db.delete(accounts).where(inArray(accounts.id,ids));}
  await db.delete(limits).where(like(limits.bucket,`${prefix}%`));
  for(const id of ids)await db.delete(limits).where(like(limits.bucket,`%${id}%`));
  await closeDatabase();
});
async function account(){const id=randomUUID();ids.push(id);await database().insert(accounts).values({id});return{accountId:id,keyId:'unused',development:true};}
test('concurrent quota reservations never exceed the cap',async()=>{
  const outcomes=await Promise.allSettled(Array.from({length:12},()=>consume(`${prefix}-quota`,3,tomorrow())));
  assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,3);
  const [row]=await database().select().from(limits).where(eq(limits.bucket,`${prefix}-quota`));assert.equal(row.count,3);
});
test('valid App Attest assertions authenticate, while tampering and replay fail',async()=>{
  const identity=await account();const keyId=`${prefix}-key`;
  const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  await database().insert(devices).values({keyId,accountId:identity.accountId,publicKey:pair.publicKey.export({type:'spki',format:'pem'}).toString()});
  const {nonce}=await challenge(new Request('http://localhost:3000'),keyId,'request');
  const url='https://api.example.com/api/v1/account/status';
  const raw=JSON.stringify({nonce});const payload=`POST\n/api/v1/account/status\n${raw}`;
  const authData=Buffer.alloc(37);createHash('sha256').update('TESTTEAM01.com.philstarkovich.cavecals').digest().copy(authData);authData.writeUInt32BE(1,33);
  const nonceHash=createHash('sha256').update(Buffer.concat([authData,createHash('sha256').update(payload).digest()])).digest();
  const assertion=cbor.encode({signature:sign('sha256',nonceHash,pair.privateKey),authenticatorData:authData}).toString('base64');
  const req=new Request(url,{method:'POST',headers:{'x-app-key':keyId,'x-app-assertion':assertion}});
  await assert.rejects(authenticate(req,raw+' ',nonce));
  const verified=await authenticate(req,raw,nonce);assert.equal(verified.accountId,identity.accountId);
  await assert.rejects(authenticate(req,raw,nonce));
});
test('an authentic unpaid account cannot invoke paid features',async()=>{
  const identity=await account();
  await assert.rejects(requirePaid({...identity,development:false}), (e:unknown)=>(e as {status:number}).status===402);
});
test('API rejects unauthenticated requests and malformed JSON',async()=>{
  const req=(body:string)=>new Request('https://example.com/api/v1/uploads/sign',{method:'POST',headers:{'content-type':'application/json'},body});
  assert.equal((await api(req('{'),'uploads/sign')).status,400);
  assert.equal((await api(req(JSON.stringify({nonce:'anything'})),'uploads/sign')).status,401);
});
test('upload ownership and idempotency prevent cross-account access and double OpenAI calls',async()=>{
  const identity=await account(),other=await account();const id=randomUUID();uploadIds.push(id);
  const bytes=Buffer.from('fixture');const row={id,accountId:identity.accountId,pathname:`temporary/${id}`,kind:'image',mime:'image/jpeg',byteLength:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),storage:'local',expiresAt:tomorrow()};
  await database().insert(uploads).values(row);await mkdir(path.dirname(localPath(id)),{recursive:true});await writeFile(localPath(id),bytes);
  let calls=0;const fixture={items:[{name:'Egg',calories:80,portion:'one egg',servingSize:'one egg',servings:1,confidence:'medium' as const}],notes:'Test fixture'};
  const model=async()=>{calls++;await new Promise(r=>setTimeout(r,100));return fixture;};
  await assert.rejects(analyze(other,id,model));assert.equal(calls,0);
  const results=await Promise.allSettled([analyze(identity,id,model),analyze(identity,id,model)]);
  assert.ok(results.some(r=>r.status==='fulfilled'));assert.equal(calls,1);
  assert.deepEqual(await analyze(identity,id,model),fixture);assert.equal(calls,1);
});
test('forged or expired upload requests never write files',async()=>{
  const id=randomUUID();
  const req=new Request(`http://localhost:3000/api/dev/upload/${id}`,{method:'PUT',headers:{Authorization:`Bearer ${devToken}`},body:'x'});
  await assert.rejects(localUpload(req,id));
  env.VERCEL='1';await assert.rejects(localUpload(req,id));delete env.VERCEL;
});
test('cleanup is authenticated and removes expired batches without deleting live uploads', async()=>{
  const {GET}=await import('../../backend/src/app/api/cron/cleanup/route');
  const secret=env.CRON_SECRET;env.CRON_SECRET=randomUUID()+randomUUID();
  try {
    assert.equal((await GET(new Request('http://localhost/api/cron/cleanup'))).status,401);
    const identity=await account();
    const rows=Array.from({length:201},()=>({id:randomUUID(),accountId:identity.accountId,pathname:'test-unused',kind:'image',mime:'image/jpeg',byteLength:1,sha256:'a'.repeat(64),storage:'local',expiresAt:new Date(Date.now()-60000)}));
    const live={...rows[0],id:randomUUID(),expiresAt:new Date(Date.now()+3600000)};
    uploadIds.push(...rows.map(r=>r.id),live.id);
    await database().insert(uploads).values([...rows,live]);
    const response=await GET(new Request('http://localhost/api/cron/cleanup',{headers:{Authorization:`Bearer ${env.CRON_SECRET}`}}));
    assert.equal(response.status,200);
    assert.equal((await database().select().from(uploads).where(inArray(uploads.id,rows.map(r=>r.id)))).length,0);
    assert.equal((await database().select().from(uploads).where(eq(uploads.id,live.id))).length,1);
  }finally{if(secret===undefined)delete env.CRON_SECRET;else env.CRON_SECRET=secret;}
});
