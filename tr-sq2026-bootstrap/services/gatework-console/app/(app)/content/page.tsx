import { OfficialDesk } from '@/components/content/official-desk';
import { PageHeader } from '@/components/ui/page';
import { canPublishContent, listSystemAccounts, type SystemAccount } from '@/lib/content';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function ContentPage() {
  const session = await getSession();
  if (!session) return null;

  let accounts: SystemAccount[] = [];
  let failure: string | null = null;
  try {
    accounts = await listSystemAccounts();
  } catch (error) {
    failure = `Resmî hesap listesi okunamadı: ${error instanceof Error ? error.message : 'bilinmeyen hata'}.`;
  }

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="İçerik Stüdyosu"
        description="Platformun kendi adına yaptığı yayınlar burada üretilir. Resmî hesaplar giriş yapamaz; yalnızca panel üzerinden, her yayın gerekçesiyle birlikte denetim kaydına yazılarak paylaşım yapar."
      />
      <OfficialDesk
        initialAccounts={accounts}
        loadFailure={failure}
        canPublish={canPublishContent(session.member.roles)}
      />
    </main>
  );
}
