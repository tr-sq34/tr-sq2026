'use client';
import { useState } from 'react';
import { LockKeyhole, Mail, ShieldCheck } from 'lucide-react';
import { api, errorText } from '@/lib/api-client';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/field';

/**
 * The first screen an operator sees, and the last one still on the old palette.
 *
 * Ported to the console's own tokens so the sign-in page and the panel behind
 * it look like the same product; the fields go through `Field`/`Input` for the
 * focus ring, which on a password box is the only thing that says where the
 * keystrokes are going.
 *
 * The password never leaves this form: it is posted to the console's own login
 * route, which exchanges it for a session cookie. Nothing here stores it, logs
 * it, or puts it in a query string.
 */
export function LoginForm() {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(form: FormData) {
    setLoading(true);
    setError(null);
    try {
      await api('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email: form.get('email'), password: form.get('password') }),
      });
      window.location.assign('/');
    } catch (caught) {
      setError(errorText(caught, 'Giriş yapılamadı.'));
      setLoading(false);
    }
  }

  return (
    <form action={submit} className="w-full max-w-sm rounded-card border border-hairline bg-surface p-7 shadow-2xl shadow-black/40">
      <p className="text-xs font-semibold tracking-[.22em] text-brand-300 uppercase">TurkSquare</p>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight text-ink">Gatework</h1>
      <p className="mt-2 text-sm text-ink-muted">Sadece yetkili ekip erişimi.</p>

      <div className="mt-6 grid gap-4">
        <Field label="E-posta">
          <div className="relative">
            <Mail size={16} className="absolute top-1/2 left-3 -translate-y-1/2 text-ink-faint" />
            <Input required type="email" name="email" autoComplete="username" className="h-11 pl-9" />
          </div>
        </Field>
        <Field label="Şifre">
          <div className="relative">
            <LockKeyhole size={16} className="absolute top-1/2 left-3 -translate-y-1/2 text-ink-faint" />
            <Input required type="password" name="password" autoComplete="current-password" className="h-11 pl-9" />
          </div>
        </Field>

        {error && (
          <p role="alert" className="rounded-lg border border-danger/30 bg-danger-soft p-3 text-sm text-danger">
            {error}
          </p>
        )}

        <Button type="submit" variant="primary" disabled={loading} className="h-11 w-full">
          {loading ? 'Doğrulanıyor…' : 'Güvenli giriş'}
        </Button>
      </div>

      <p className="mt-5 flex items-start gap-2 text-xs leading-5 text-ink-faint">
        <ShieldCheck size={14} className="mt-0.5 shrink-0" />
        Cloudflare Access ve çok faktörlü doğrulama, uygulama oturumundan önce zorunludur.
      </p>
    </form>
  );
}
