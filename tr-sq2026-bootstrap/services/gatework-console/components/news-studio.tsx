'use client';
import { useState } from 'react';

const CATEGORIES = [['gundem','Gündem'],['gocmenlik','Göçmenlik'],['ekonomi','Ekonomi'],['yasam','Yaşam'],['spor','Spor'],['kultur','Kültür'],['topluluk','Topluluk']] as const;

async function send(url: string, payload: Record<string, unknown>) { const response=await fetch(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)}); const body=await response.json().catch(()=>null); if(!response.ok)throw Error(body?.error?.message??'İşlem tamamlanamadı.'); return body.data; }

/// Where the app's Haber Merkezi and the home screen's "Amerika'dan Manşetler"
/// strip are written. One form for both: the manşet sırası field is what puts a
/// piece on the home screen, so an editor never has to publish twice.
export function NewsStudio() {
  const [status,setStatus]=useState<string>();
  const [pending,setPending]=useState(false);
  async function publish(form:FormData){
    setStatus(undefined); setPending(true);
    try{
      const rank=String(form.get('headlineRank')??'').trim();
      const article=await send('/api/content/news',{
        authorId:form.get('authorId'),
        title:form.get('title'),
        summary:form.get('summary'),
        body:form.get('body'),
        category:form.get('category'),
        heroMediaId:String(form.get('heroMediaId')??'').trim()||undefined,
        regionCode:String(form.get('regionCode')??'').trim()||undefined,
        headlineRank:rank?Number(rank):undefined,
        commentsEnabled:form.get('commentsEnabled')==='on',
        reason:form.get('reason'),
      });
      setStatus(`Haber yayınlandı: ${article.id}`);
    }catch(e){setStatus(e instanceof Error?e.message:'İşlem tamamlanamadı.');}
    finally{setPending(false);}
  }
  const field='mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  return <form action={publish} className="grid max-w-3xl gap-4 rounded-xl border border-white/10 bg-zinc-900/40 p-6">
    <div><h2 className="font-semibold">Haber yayınla</h2><p className="mt-1 text-sm text-zinc-500">Yayınlanan haber Haber Merkezi listesine düşer; manşet sırası verilirse ana sayfada da görünür.</p></div>
    <label className="block text-sm">Resmî hesap ID<input className={field} name="authorId" required placeholder="İçerik Stüdyosu&apos;nda oluşturulan resmî hesap" /></label>
    <label className="block text-sm">Başlık<input className={field} name="title" required minLength={3} maxLength={200} /></label>
    <label className="block text-sm">Özet<textarea className={field} name="summary" required minLength={3} maxLength={500} rows={2} placeholder="Listede ve ana sayfada görünen tek paragraf" /></label>
    <label className="block text-sm">Haber metni<textarea className={field} name="body" required minLength={1} maxLength={20000} rows={12} /></label>
    <div className="grid gap-4 sm:grid-cols-2">
      <label className="block text-sm">Kategori<select className={field} name="category" defaultValue="gundem">{CATEGORIES.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
      <label className="block text-sm">Manşet sırası <span className="text-zinc-600">(boşsa ana sayfada çıkmaz)</span><input className={field} name="headlineRank" type="number" min={1} max={20} placeholder="1" /></label>
      <label className="block text-sm">Görsel medya ID <span className="text-zinc-600">(isteğe bağlı)</span><input className={field} name="heroMediaId" placeholder="Taranmış medya kimliği" /></label>
      <label className="block text-sm">Eyalet kodu <span className="text-zinc-600">(isteğe bağlı)</span><input className={field} name="regionCode" maxLength={2} placeholder="NJ" /></label>
    </div>
    <label className="flex items-center gap-2 text-sm text-zinc-300"><input type="checkbox" name="commentsEnabled" defaultChecked className="size-4 rounded border-zinc-700 bg-zinc-950" />Yorumlara açık</label>
    <label className="block text-sm">İşlem nedeni<textarea className={field} name="reason" required minLength={5} maxLength={500} rows={2} placeholder="Denetim kaydına yazılır" /></label>
    <button disabled={pending} className="justify-self-start rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">{pending?'Yayınlanıyor...':'Haberi yayınla'}</button>
    {status&&<p className="rounded-lg border border-white/10 bg-zinc-900 p-4 text-sm text-zinc-300">{status}</p>}
  </form>;
}
