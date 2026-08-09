import { notFound } from 'next/navigation';
import { ContentStudio } from '@/components/content-studio';

const sections: Record<string, { title: string; text: string }> = {
  content: { title: 'İçerik Stüdyosu', text: 'Resmî hesaplar, Akış postları ve Story yayınlama sözleşmesi Gatework API üzerinden etkinleştirilecek.' },
  members: { title: 'Üyeler', text: 'Üye arama, durum, oturum iptali ve destek notları; parolalar veya tokenlar asla gösterilmez.' },
  // moderation and communications now have their own routes backed by the
  // messaging gateway; a static segment wins over this catch-all, so leaving
  // their placeholders here would only be dead copy.
  marketplace: { title: 'Çarşı ve İhaleler', text: 'İlan ve ihale operasyonları Community API hazır olduğunda role bağlı açılır.' },
  safety: { title: 'Güvenlik ve SOS', text: 'SOS iş akışı, ayrı yetki ve süreli konum erişimi gerektirir.' },
  analytics: { title: 'Analitik ve Konum', text: 'Yalnızca toplulaştırılmış şehir/eyalet metrikleri gösterilecektir.' },
  verification: { title: 'Doğrulama', text: 'Stripe Identity sonuçları ileride belge içeriği olmadan burada görünür.' },
  system: { title: 'Sistem ve Denetim', text: 'Audit kayıtları ve feature flag yönetimi Owner yetkisiyle etkinleştirilecektir.' },
};
export default async function Section({ params }: { params: Promise<{ section: string[] }> }) { const section = (await params).section?.[0]; if (!section || !sections[section]) notFound(); const value = sections[section]; if(section==='content') return <main><p className="text-sm text-emerald-400">Community API bağlı operasyon</p><h1 className="mt-2 text-3xl font-semibold">{value.title}</h1><p className="mt-4 mb-8 max-w-xl text-zinc-400">{value.text}</p><ContentStudio /></main>; return <main><p className="text-sm text-amber-300">Servis bağlanması bekleniyor</p><h1 className="mt-2 text-3xl font-semibold">{value.title}</h1><p className="mt-4 max-w-xl text-zinc-400">{value.text}</p><div className="mt-8 rounded-xl border border-dashed border-zinc-700 bg-zinc-900/30 p-6 text-sm text-zinc-500">Bu alan sahte veriye izin vermez. İlgili domain API ve audit sözleşmesi etkinleştiğinde kullanılabilir olacaktır.</div></main>; }
