import { PromotionStudio } from '@/components/promotion-studio';
import { PageHeader } from '@/components/ui/page';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function PromotionsPage() {
  const session = await getSession();
  if (!session) return null;

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="Tanıtımlar"
        description="Üyelerin Story alanı ve banner talepleri burada onaylanır; “Sana Özel Öne Çıkanlar” kartları yalnızca panelden yerleştirilir. Bu fazda ödeme alınmaz."
      />
      <PromotionStudio />
    </main>
  );
}
