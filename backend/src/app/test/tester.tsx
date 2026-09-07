'use client';
import { useRef, useState, useEffect } from 'react';
import type { FoodResult } from '@/server/ai';
export default function Tester() {
  const [token,setToken] = useState(''); const [file,setFile] = useState<File|null>(null);
  const [result,setResult] = useState<FoodResult|null>(null); const [message,setMessage] = useState('');
  const [busy,setBusy] = useState(false); const [recording,setRecording] = useState(false);
  const recorder = useRef<MediaRecorder|null>(null); const timer = useRef<ReturnType<typeof setTimeout>|null>(null);
  useEffect(() => () => { if(timer.current) clearTimeout(timer.current); recorder.current?.stream.getTracks().forEach(t=>t.stop()); }, []);
  async function api(path: string, body: object) {
    const response = await fetch(`/api/v1/${path}`, {method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({nonce:crypto.randomUUID(),...body})});
    const data = await response.json(); if(!response.ok) throw new Error(data.error?.message || 'Request failed.'); return data;
  }
  async function analyze() {
    if(!file) return; setBusy(true);setResult(null);
    try {
      setMessage('Checking access and preparing upload…');
      const bytes = await file.arrayBuffer();
      const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
      const mime = file.type.split(';')[0] || (file.name.endsWith('.m4a') ? 'audio/mp4' : '');
      const upload = await api('uploads/sign',{kind:mime.startsWith('image/')?'image':'audio',mime,byteLength:file.size,sha256});
      setMessage('Uploading…');
      const headers: Record<string,string> = {'Content-Type':upload.contentType};
      if(new URL(upload.uploadURL).origin === location.origin) headers.Authorization = `Bearer ${token}`;
      const put = await fetch(upload.uploadURL,{method:'PUT',headers,body:file});
      if(!put.ok) throw new Error('Upload failed. Please select the file again.');
      setMessage('Identifying food…');
      setResult(await api('food/analyze',{uploadId:upload.uploadId}));setMessage('Estimate ready. Review portions and calories.');
    } catch(error) {setMessage(error instanceof Error?error.message:'Request failed.');} finally {setBusy(false);}
  }
  async function record() {
    if(recording) {recorder.current?.stop();return;}
    try {
      const stream = await navigator.mediaDevices.getUserMedia({audio:true});
      const mime = MediaRecorder.isTypeSupported('audio/mp4')?'audio/mp4':'audio/webm';
      const r = new MediaRecorder(stream,{mimeType:mime}); const parts:BlobPart[]=[];recorder.current=r;
      r.ondataavailable=e=>{if(e.data.size)parts.push(e.data);};
      r.onstop=async()=>{
        stream.getTracks().forEach(t=>t.stop()); if(timer.current)clearTimeout(timer.current);
        try {
          // Browser WebM recordings often omit duration. Convert to bounded mono WAV so
          // the server can validate duration before making a paid transcription request.
          const context=new AudioContext();
          let decoded:AudioBuffer;
          try { decoded=await context.decodeAudioData(await new Blob(parts,{type:mime}).arrayBuffer()); } finally { await context.close(); }
          const offline=new OfflineAudioContext(1,Math.ceil(decoded.duration*16000),16000);
          const source=offline.createBufferSource();source.buffer=decoded;source.connect(offline.destination);source.start();
          const rendered=await offline.startRendering();const samples=rendered.getChannelData(0);
          const bytes=new ArrayBuffer(44+samples.length*2);const view=new DataView(bytes);
          const str=(offset:number,text:string)=>{for(let i=0;i<text.length;i++)view.setUint8(offset+i,text.charCodeAt(i));};
          str(0,'RIFF');view.setUint32(4,36+samples.length*2,true);str(8,'WAVE');str(12,'fmt ');view.setUint32(16,16,true);view.setUint16(20,1,true);view.setUint16(22,1,true);view.setUint32(24,16000,true);view.setUint32(28,32000,true);view.setUint16(32,2,true);view.setUint16(34,16,true);str(36,'data');view.setUint32(40,samples.length*2,true);
          for(let i=0;i<samples.length;i++){const sample=Math.max(-1,Math.min(1,samples[i]));view.setInt16(44+i*2,sample*(sample<0?32768:32767),true);}
          setFile(new File([bytes],'recording.wav',{type:'audio/wav'}));
        }catch{setMessage('The recording could not be prepared. Please try again.');}
        finally{setRecording(false);}
      };
      r.start();setRecording(true);timer.current=setTimeout(()=>{if(r.state==='recording')r.stop();},60000);
    }catch{setMessage('Microphone unavailable. Allow access or choose an audio file.');}
  }
  return <main><p className="eyebrow">LOCAL DEVELOPMENT ONLY</p><h1>Try photo & voice.</h1>
    <p>This page calls the same API as the iPhone app. It is unavailable in production.</p>
    <label>Local test token<input type="password" autoComplete="off" value={token} onChange={e=>setToken(e.target.value)} placeholder="DEV_API_TOKEN from .env.development.local"/></label>
    <p className="muted">Set OPENAI_API_KEY in the server environment file. Enter only the local test token here. Selected media is sent to OpenAI when you press Analyze.</p>
    <label>Photo, screenshot, or recording<input type="file" accept="image/jpeg,image/png,image/webp,audio/mp4,audio/x-m4a,audio/m4a,audio/webm,audio/wav,audio/mpeg" disabled={busy||recording} onChange={e=>setFile(e.target.files?.[0]||null)}/></label>
    <div className="actions"><button disabled={busy} onClick={record}>{recording?'Stop recording':'Record voice (up to 60s)'}</button><button disabled={!file||!token||busy||recording} onClick={analyze}>Analyze</button></div>
    {file&&<p>Selected: {file.name}</p>}<p role="status" aria-live="polite">{message}</p>
    {result&&<section><h2>Review estimate</h2>{result.transcript&&<blockquote>{result.transcript}</blockquote>}
      {result.items.map((item,i)=><article key={i}><strong>{item.name}</strong><span>{item.calories} kcal</span><p>{item.portion} · {item.confidence} confidence</p></article>)}
      <p>{result.notes}</p><p className="muted">Nothing is added to the iPhone diary from this test page.</p></section>}
  </main>;
}
