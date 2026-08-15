import { OfficialDesk } from '@/components/content/official-desk';
import { StoryDesk } from '@/components/content/story-desk';
import { PageHeader } from '@/components/ui/page';
import {
  canPublishContent,
  listOfficialStories,
  listSystemAccounts,
  type OfficialStory,
  type SystemAccount,
} from '@/lib/content';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

const reason = (error: unknown) => (error instanceof Error ? error.message : 'bilinmeyen hata');

export default async function ContentPage() {
  const session = await getSession();
  if (!session) return null;

  // İki liste ayrı ayrı okunuyor: Story servisi cevap vermediğinde hesap listesi
  // ve akış paylaşımı çalışmaya devam etmeli, ekran boş açılmamalı.
  let accounts: SystemAccount[] = [];
  let failure: string | null = null;
  try {
    accounts = await listSystemAccounts();
  } catch (error) {
    failure = `Resmî hesap listesi okunamadı: ${reason(error)}.`;
  }

  let stories: OfficialStory[] = [];
  let storyFailure: string | null = null;
  try {
    stories = await listOfficialStories();
  } catch (error) {
    storyFailure = `Yayındaki Storyler okunamadı: ${reason(error)}. Aşağıdaki liste eksik olabilir.`;
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
      <div className="mt-6">
        <StoryDesk
          initialStories={stories}
          accounts={accounts}
          loadFailure={storyFailure}
          canPublish={canPublishContent(session.member.roles)}
        />
      </div>
    </main>
  );
}
