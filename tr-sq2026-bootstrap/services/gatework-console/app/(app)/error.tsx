'use client';
import { useEffect } from 'react';
import { RefreshCw, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';

/**
 * What an operator sees when a screen throws anyway.
 *
 * Before this, a server error rendered the Next.js default: an English sentence
 * and a bare number, on a page with no way back into the panel. The number is
 * worth keeping - it is the digest, and it is the string that matches the line
 * in the container log - so it stays, next to a sentence that says what it is
 * for. Everything else here exists so the operator is not stranded: the panel
 * chrome is still around this, and the retry re-runs the screen rather than
 * reloading the whole console.
 */
export default function ScreenError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // The server already logged the real error; this is the browser half of the
    // same event, so a support call has something to read out.
    console.error('Gatework ekran hatası', error.digest, error);
  }, [error]);

  return (
    <Card tone="urgent">
      <CardContent className="grid gap-4 py-8 text-center justify-items-center">
        <span className="grid size-12 place-items-center rounded-full bg-danger-soft text-danger">
          <TriangleAlert size={22} />
        </span>
        <div className="grid gap-1.5">
          <h1 className="text-lg font-semibold text-ink">Bu ekran açılamadı</h1>
          <p className="mx-auto max-w-md text-sm text-ink-muted">
            Sunucu tarafında bir hata oluştu. Panelin geri kalanı çalışmaya devam ediyor; soldaki menüden başka bir ekrana geçebilirsiniz.
          </p>
        </div>
        {error.digest && (
          <p className="text-xs text-ink-faint">
            Hata kodu <span className="font-mono text-ink-muted">{error.digest}</span> — sunucu kayıtlarında aynı kodla geçer.
          </p>
        )}
        <Button variant="primary" size="sm" onClick={reset}>
          <RefreshCw size={15} /> Yeniden dene
        </Button>
      </CardContent>
    </Card>
  );
}
