import { MarketplaceDesk } from '@/components/marketplace-desk';
import { canActOnMarketplace, canSeeMarketplace, marketplacePage } from '@/lib/marketplace';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function MarketplacePage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeMarketplace(roles)) {
    return <main><h1 className="text-3xl font-semibold">Çarşı ve İhaleler</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan çarşı yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  const { overview, listings, auctions, failure } = await marketplacePage();

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Community API bağlı operasyon</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Çarşı ve İhaleler</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Üyelerin ilanları ve ihaleleri. Buradan bir ilan yayından kaldırılır ya da geri alınır, bir ihale iptal edilir — her ikisi de gerekçeyle ve denetim kaydıyla. İlanın başlığı, fiyatı ve açıklaması değiştirilemez: başkasının ilanını, adı üstünde dururken yeniden yazmak kaldırmaktan daha ağırdır.
        </p>
      </div>

      <MarketplaceDesk
        initialOverview={overview}
        initialListings={listings}
        initialAuctions={auctions}
        initialFailure={failure}
        canAct={canActOnMarketplace(roles)}
      />
    </main>
  );
}
