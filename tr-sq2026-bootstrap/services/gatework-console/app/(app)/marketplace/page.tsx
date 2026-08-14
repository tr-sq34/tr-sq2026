import { MarketplaceDesk } from '@/components/marketplace/marketplace-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canActOnMarketplace, canSeeMarketplace, marketplacePage } from '@/lib/marketplace';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function MarketplacePage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeMarketplace(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Çarşı ve İhaleler" />
        <EmptyState title="Bu alan çarşı yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { overview, listings, auctions, failure } = await marketplacePage();

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="Çarşı ve İhaleler"
        description="Üyelerin ilanları ve ihaleleri. Buradan bir ilan yayından kaldırılır ya da geri alınır, bir ihale iptal edilir — her ikisi de gerekçeyle ve denetim kaydıyla. Satırların yanındaki uyarılar ölçümdür: fiyat kategori ortancasının çok altında mı, aynı başlık başka hesaplarda var mı, satıcı hakkında açık şikâyet var mı. Karar hâlâ senin."
      />
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
