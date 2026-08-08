'use client';
import { useState } from 'react';
import { LockKeyhole, Mail } from 'lucide-react';

export function LoginForm() {
  const [error, setError] = useState<string>(); const [loading, setLoading] = useState(false);
  async function submit(form: FormData) {
    setLoading(true); setError(undefined);
    const response = await fetch('/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: form.get('email'), password: form.get('password') }) });
    const body = await response.json().catch(() => null);
    if (!response.ok) { setError(body?.error?.message ?? 'Giriş yapılamadı.'); setLoading(false); return; }
    window.location.assign('/');
  }
  return <form action={submit} className="w-full max-w-sm space-y-4 rounded-2xl border border-white/10 bg-zinc-950/80 p-7 shadow-2xl shadow-black/40">
    <div><p className="text-xs font-semibold uppercase tracking-[.22em] text-emerald-400">TurkSquare</p><h1 className="mt-2 text-2xl font-semibold">Gatework</h1><p className="mt-2 text-sm text-zinc-400">Sadece yetkili ekip erişimi.</p></div>
    <label className="block text-sm"><span className="mb-2 block text-zinc-300">E-posta</span><span className="flex items-center gap-2 rounded-lg border border-zinc-700 bg-zinc-900 px-3"><Mail size={17} className="text-zinc-500" /><input required type="email" name="email" autoComplete="username" className="h-11 w-full bg-transparent outline-none" /></span></label>
    <label className="block text-sm"><span className="mb-2 block text-zinc-300">Şifre</span><span className="flex items-center gap-2 rounded-lg border border-zinc-700 bg-zinc-900 px-3"><LockKeyhole size={17} className="text-zinc-500" /><input required type="password" name="password" autoComplete="current-password" className="h-11 w-full bg-transparent outline-none" /></span></label>
    {error && <p role="alert" className="rounded-lg border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200">{error}</p>}
    <button disabled={loading} className="h-11 w-full rounded-lg bg-emerald-400 font-semibold text-zinc-950 disabled:opacity-60">{loading ? 'Doğrulanıyor…' : 'Güvenli giriş'}</button>
    <p className="text-center text-xs leading-5 text-zinc-500">Cloudflare Access ve çok faktörlü doğrulama, uygulama oturumundan önce zorunludur.</p>
  </form>;
}
