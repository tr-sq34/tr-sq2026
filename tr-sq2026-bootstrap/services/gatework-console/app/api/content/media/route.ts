import { NextResponse } from 'next/server';
import { MEDIA_CONTENT_TYPES, MEDIA_MAX_BYTES, uploadNewsImage } from '@/lib/gatework';

const noStore = { 'cache-control': 'no-store' };

/**
 * Haber görselinin yüklendiği yer.
 *
 * Dosya tarayıcıdan buraya, buradan depoya gidiyor; kısa ömürlü yazma
 * bağlantısı tarayıcıya hiç inmiyor. Yanıt yalnızca bir kimlik döndürüyor,
 * çünkü görsel bu noktada henüz taranmadı - okunabilir hâli medya işleyici
 * bitirince oluşuyor ve panel onu ayrı bir uçtan yokluyor.
 *
 * Reddetme nedenleri ayrı ayrı yazılıyor. "Görsel yüklenemedi" cümlesi,
 * dosyanın büyük mü, biçiminin mi yanlış olduğunu ya da yayınlayacak hesabın
 * seçilmediğini söylemediği için editörü aynı hatayı tekrarlamaya bırakıyordu.
 */
export async function POST(request: Request) {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return NextResponse.json(
      { error: { code: 'MEDIA_BODY_UNREADABLE', message: 'Dosya okunamadı. Yükleme yarıda kalmış olabilir.' } },
      { status: 400, headers: noStore },
    );
  }

  const file = form.get('file');
  const ownerId = String(form.get('ownerId') ?? '').trim();

  if (!ownerId) {
    return NextResponse.json(
      { error: { code: 'MEDIA_OWNER_MISSING', message: 'Önce haberi yayınlayacak resmî hesabı seç; görsel o hesabın adına yükleniyor.' } },
      { status: 400, headers: noStore },
    );
  }
  if (!(file instanceof File) || file.size === 0) {
    return NextResponse.json(
      { error: { code: 'MEDIA_FILE_MISSING', message: 'Yüklenecek dosya gelmedi.' } },
      { status: 400, headers: noStore },
    );
  }
  if (!MEDIA_CONTENT_TYPES.includes(file.type as (typeof MEDIA_CONTENT_TYPES)[number])) {
    return NextResponse.json(
      { error: { code: 'MEDIA_TYPE_REJECTED', message: `Yalnızca JPEG, PNG ve WebP yüklenebilir. Bu dosya: ${file.type || 'tür bilgisi yok'}.` } },
      { status: 400, headers: noStore },
    );
  }
  if (file.size > MEDIA_MAX_BYTES) {
    const megabytes = (file.size / 1024 / 1024).toFixed(1);
    return NextResponse.json(
      { error: { code: 'MEDIA_TOO_LARGE', message: `Dosya ${megabytes} MB; sınır 10 MB.` } },
      { status: 413, headers: noStore },
    );
  }

  try {
    const result = await uploadNewsImage({
      ownerId,
      fileName: file.name || 'gorsel',
      contentType: file.type,
      bytes: Buffer.from(await file.arrayBuffer()),
    });
    return NextResponse.json({ data: result }, { status: 202, headers: noStore });
  } catch (error) {
    // Hangi adımın düştüğü mesajda kalıyor: yükleme izni, depoya yazma ve
    // tamamlama ayrı ayrı sorunlar ve editörün yapabileceği şey de ayrı.
    const reason = error instanceof Error ? error.message : 'bilinmiyor';
    return NextResponse.json(
      { error: { code: 'MEDIA_UPLOAD_FAILED', message: `Görsel yüklenemedi (${reason}).` } },
      { status: 502, headers: noStore },
    );
  }
}
