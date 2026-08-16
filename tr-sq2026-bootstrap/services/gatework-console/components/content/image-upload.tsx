'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ImagePlus, Loader2, ScanLine, ShieldAlert, Trash2 } from 'lucide-react';
import { apiData, errorText } from '@/lib/api-client';

/**
 * Panelden görsel yükleme.
 *
 * Buranın yerinde "Görsel medya kimliği" yazan bir metin kutusu vardı ve
 * ipucunda "panelde görsel yükleme yok, medya kimliği medya hattından gelir"
 * yazıyordu. Öyle bir hat yoktu: kimliği elde etmenin tek yolu uygulamadan
 * görsel yükleyip kimliğini kopyalamaktı, o da resmî hesabın değil o üyenin
 * medyası olduğu için haber yayınlanırken geri dönerdi. Sonuç: paneldeki her
 * haber görselsiz çıkıyordu.
 *
 * Yükleme uygulamadakiyle aynı hattan geçiyor - karantina, tarama, EXIF
 * temizliği, webp'ye çevirme - bu yüzden görsel seçilir seçilmez hazır olmuyor.
 * Bileşen bu bekleyişi gizlemiyor: seçilen dosya hemen önizlemede görünüyor,
 * altında hangi adımda olduğu yazıyor ve yayınlama düğmesi ancak "ready"
 * olduğunda açılıyor.
 */
const POLL_MS = 1500;
const POLL_LIMIT = 40; // 40 × 1,5 sn = bir dakika

type Phase = 'empty' | 'uploading' | 'scanning' | 'ready' | 'failed';

export type UploadedImage = { mediaId: string; url: string | null };

export function ImageUpload({
  ownerId,
  value,
  onChange,
  disabled = false,
}: {
  ownerId: string;
  value: UploadedImage | null;
  onChange: (next: UploadedImage | null) => void;
  disabled?: boolean;
}) {
  const [phase, setPhase] = useState<Phase>(value ? 'ready' : 'empty');
  const [error, setError] = useState<string | null>(null);
  const [localPreview, setLocalPreview] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const objectUrl = useRef<string | null>(null);
  const cancelled = useRef(false);

  useEffect(() => {
    cancelled.current = false;
    return () => {
      cancelled.current = true;
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);
    };
  }, []);

  const clearLocalPreview = useCallback(() => {
    if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);
    objectUrl.current = null;
    setLocalPreview(null);
  }, []);

  const reset = useCallback(() => {
    clearLocalPreview();
    setPhase('empty');
    setError(null);
    onChange(null);
    if (inputRef.current) inputRef.current.value = '';
  }, [clearLocalPreview, onChange]);

  const accept = useCallback(
    async (file: File) => {
      if (!ownerId) {
        setError('Önce haberi yayınlayacak resmî hesabı seç; görsel o hesabın adına yükleniyor.');
        setPhase('failed');
        return;
      }
      clearLocalPreview();
      const preview = URL.createObjectURL(file);
      objectUrl.current = preview;
      setLocalPreview(preview);
      setError(null);
      setPhase('uploading');
      onChange(null);

      try {
        const body = new FormData();
        body.append('file', file);
        body.append('ownerId', ownerId);
        const { mediaId } = await apiData<{ mediaId: string }>('/api/content/media', {
          method: 'POST',
          body,
        });
        if (cancelled.current) return;
        setPhase('scanning');
        await waitUntilReady(mediaId);
      } catch (caught) {
        if (cancelled.current) return;
        setError(errorText(caught, 'Görsel yüklenemedi.'));
        setPhase('failed');
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ownerId, clearLocalPreview, onChange],
  );

  async function waitUntilReady(mediaId: string) {
    for (let attempt = 0; attempt < POLL_LIMIT; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
      if (cancelled.current) return;
      const status = await apiData<{ status: string; url: string | null }>(
        `/api/content/media/${mediaId}?ownerId=${encodeURIComponent(ownerId)}`,
      );
      if (cancelled.current) return;
      if (status.status === 'ready') {
        clearLocalPreview();
        setPhase('ready');
        onChange({ mediaId, url: status.url });
        return;
      }
      if (status.status === 'rejected') {
        throw new Error('Görsel güvenlik taramasını geçemedi ve yayına alınmadı.');
      }
    }
    throw new Error('Tarama bir dakikada bitmedi. Görsel hâlâ işleniyor olabilir; biraz sonra tekrar dene.');
  }

  const shownImage = value?.url ?? localPreview;
  const busy = phase === 'uploading' || phase === 'scanning';

  return (
    <div className="grid gap-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file) void accept(file);
        }}
      />

      <div
        onDragOver={(event) => {
          event.preventDefault();
          if (!disabled && !busy) setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(event) => {
          event.preventDefault();
          setDragging(false);
          if (disabled || busy) return;
          const file = event.dataTransfer.files?.[0];
          if (file) void accept(file);
        }}
        className={`relative overflow-hidden rounded-lg border border-dashed transition ${
          dragging ? 'border-brand-400 bg-brand-500/5' : phase === 'failed' ? 'border-danger/40' : 'border-hairline'
        }`}
      >
        {shownImage ? (
          <div className="relative">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={shownImage}
              alt="Haber görseli önizlemesi"
              className={`h-44 w-full object-cover transition ${busy ? 'opacity-50' : ''}`}
            />
            {busy && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 bg-surface/70 text-xs text-ink">
                {phase === 'uploading' ? <Loader2 size={18} className="animate-spin" /> : <ScanLine size={18} />}
                {phase === 'uploading' ? 'Depoya yükleniyor…' : 'Güvenlik taramasından geçiyor…'}
              </div>
            )}
            {!busy && !disabled && (
              <div className="absolute top-2 right-2 flex gap-1.5">
                <button
                  type="button"
                  onClick={() => inputRef.current?.click()}
                  className="rounded-lg bg-surface/90 px-2.5 py-1.5 text-xs text-ink transition hover:bg-surface"
                >
                  Değiştir
                </button>
                <button
                  type="button"
                  onClick={reset}
                  className="rounded-lg bg-surface/90 p-1.5 text-danger transition hover:bg-surface"
                  aria-label="Görseli kaldır"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            )}
          </div>
        ) : (
          <button
            type="button"
            disabled={disabled || busy}
            onClick={() => inputRef.current?.click()}
            className="flex h-44 w-full flex-col items-center justify-center gap-2 text-ink-faint transition hover:text-ink disabled:opacity-40"
          >
            <ImagePlus size={22} />
            <span className="text-sm">Görsel seç ya da buraya sürükle</span>
            <span className="text-xs">JPEG, PNG veya WebP · en fazla 10 MB</span>
          </button>
        )}
      </div>

      {phase === 'ready' && !error && (
        <p className="text-xs text-success">Görsel tarandı ve habere eklenmeye hazır.</p>
      )}
      {error && (
        <p className="flex gap-1.5 text-xs text-danger">
          <ShieldAlert size={13} className="mt-0.5 shrink-0" />
          {error}
        </p>
      )}
    </div>
  );
}
