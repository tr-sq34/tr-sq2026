import { notFound } from 'next/navigation';
import { ContentStudio } from '@/components/content-studio';
import { NewsStudio } from '@/components/news-studio';
import { PromotionStudio } from '@/components/promotion-studio';

const sections: Record<string, { title: string; text: string }> = {
  content: { title: 'İçerik Stüdyosu', text: 'Resmî hesaplar, Akış postları ve Story yayınlama sözleşmesi Gatework API üzerinden etkinleştirilecek.' },
  news: { title: 'Haber Merkezi', text: 'Haberler resmî hesap adına yayınlanır; uygulamadaki Haber Merkezi ve ana sayfadaki manşetler aynı kayıttan beslenir.' },
  promotions: { title: 'Tanıtımlar', text: 'Üyelerin Story alanı ve banner talepleri burada onaylanır; "Sana Özel Öne Çıkanlar" kartları yalnızca panelden yerleştirilir. Bu fazda ödeme alınmaz.' },
  // moderation, communications, members, forum, system and verification now
  // have their own routes backed by Identity, Community, the messaging gateway
  // and the verification vault; a static segment wins over this catch-all, so
  // leaving their placeholders here would only be dead copy.
  marketplace: { title: 'Çarşı ve İhaleler', text: 'İlan ve ihale operasyonları Community API hazır olduğunda role bağlı açılır.' },
  safety: { title: 'Güvenlik ve SOS', text: 'SOS iş akışı, ayrı yetki ve süreli konum erişimi gerektirir.' },
  analytics: { title: 'Analitik ve Konum', text: 'Yalnızca toplulaştırılmış şehir/eyalet metrikleri gösterilecektir.' },
};
// The two live sections render their own studio; everything else is still an
// honest "not connected yet" placeholder.
const studios: Record<string, () => React.ReactElement> = { content: ContentStudio, news: NewsStudio, promotions: PromotionStudio };
export default async function Section({ params }: { params: Promise<{ section: string[] }> }) { const section = (await params).section?.[0]; if (!section || !sections[section]) notFound(); const value = sections[section]; const Studio = studios[section]; if(Studio) return <main><p className="text-sm text-emerald-400">Community API bağlı operasyon</p><h1 className="mt-2 text-3xl font-semibold">{value.title}</h1><p className="mt-4 mb-8 max-w-xl text-zinc-400">{value.text}</p><Studio /></main>; return <main><p className="text-sm text-amber-300">Servis bağlanması bekleniyor</p><h1 className="mt-2 text-3xl font-semibold">{value.title}</h1><p className="mt-4 max-w-xl text-zinc-400">{value.text}</p><div className="mt-8 rounded-xl border border-dashed border-zinc-700 bg-zinc-900/30 p-6 text-sm text-zinc-500">Bu alan sahte veriye izin vermez. İlgili domain API ve audit sözleşmesi etkinleştiğinde kullanılabilir olacaktır.</div></main>; }
