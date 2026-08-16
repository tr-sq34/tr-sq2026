/**
 * Yasal metinlerin tarayıcı tarafının da okuyabildiği yarısı.
 *
 * `lib/legal.ts` oturumu okuyor, yani sunucuya bağlı. Etiketleri ve tipleri
 * orada bırakmak, masayı çizen istemci bileşeninin `next/headers`'ı paketin
 * içine çekmesi demekti — derleme bunu doğrudan reddediyor.
 */
export type LegalKind = 'terms' | 'privacy';

export const LEGAL_KIND_LABELS: Record<LegalKind, string> = {
  terms: 'Kullanım Koşulları',
  privacy: 'Gizlilik Politikası',
};

export type LegalDocument = {
  kind: LegalKind;
  /** Uygulamanın gösterdiği sürüm. `null` ise üye bağlantıya dokunduğunda metin bulamıyor. */
  published: { id: string; version: number; title: string; body: string; changeNote: string | null; publishedAt: string } | null;
  /** Üzerinde çalışılan sürüm. Yayımlanana kadar üyeye gitmiyor. */
  draft: { id: string; version: number; title: string; body: string; changeNote: string | null; updatedAt: string } | null;
  history: { version: number; title: string; publishedAt: string; changeNote: string | null }[];
};
