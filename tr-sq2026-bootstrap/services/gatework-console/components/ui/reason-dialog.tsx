'use client';
import { useState } from 'react';
import { Button } from './button';
import { Dialog, DialogContent, DialogBody, DialogFooter } from './dialog';
import { Field, Textarea } from './field';

/**
 * The confirmation every privileged action in this console goes through.
 *
 * It replaces `window.prompt`, which the member, event and marketplace desks
 * all used to collect a reason. Three problems with that: the prompt cannot
 * show which row is about to be acted on, it cannot enforce the five-character
 * minimum the services require - so the round trip failed after the operator
 * had already committed - and it is suppressible per browser, in which case the
 * action ran with an empty reason or not at all.
 *
 * The reason is not a formality. It is the sentence that ends up in the audit
 * record next to a suspension, and it is the only part of that record a person
 * wrote.
 */
export function ReasonDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  variant = 'primary',
  onConfirm,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description: string;
  confirmLabel: string;
  variant?: 'primary' | 'danger' | 'success';
  onConfirm: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const tooShort = reason.trim().length < 5;

  function change(next: boolean) {
    if (busy) return;
    if (!next) { setReason(''); setError(null); }
    onOpenChange(next);
  }

  async function confirm() {
    if (tooShort) { setError('Gerekçe en az 5 karakter olmalı.'); return; }
    setBusy(true); setError(null);
    try {
      await onConfirm(reason.trim());
      setReason('');
      onOpenChange(false);
    } catch (caught) {
      // The dialog stays open on failure with the text intact: retyping a
      // paragraph because a service was restarting is how reasons become "x".
      setError(caught instanceof Error ? caught.message : 'İşlem tamamlanamadı.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={change}>
      <DialogContent title={title} description={description}>
        <DialogBody>
          <Field
            label="Gerekçe"
            hint="Denetim kaydına aynen yazılır ve silinemez."
            error={error ?? undefined}
          >
            <Textarea
              autoFocus
              rows={4}
              maxLength={500}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Bu kararın nedenini bir cümleyle yaz."
            />
          </Field>
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="ghost" disabled={busy} onClick={() => change(false)}>Vazgeç</Button>
          <Button type="button" variant={variant} disabled={busy || tooShort} onClick={() => void confirm()}>
            {busy ? 'Uygulanıyor…' : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
