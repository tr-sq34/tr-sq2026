import { ForumDesk } from '@/components/forum/forum-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canEditForum, canModerateForum, canSeeForum, listForumCategories, type ForumCategory } from '@/lib/forum';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function ForumPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeForum(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Forum" />
        <EmptyState title="Bu alan forum yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  let categories: ForumCategory[] = [];
  let failure: string | null = null;
  try {
    categories = await listForumCategories();
  } catch (error) {
    failure = `Bölüm listesi okunamadı: ${error instanceof Error ? error.message : 'topluluk servisi yanıt vermedi'}.`;
  }

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="Forum"
        description="Uygulamadaki forum bölümleri buradan açılır, sıralanır ve kapatılır; ana sayfadaki “Forumda trend tartışmalar” şeridi de aynı kayıtlardan beslenir. Her değişiklik gerekçesiyle birlikte denetim kaydına yazılır."
      />
      <ForumDesk
        initialCategories={categories}
        loadFailure={failure}
        canEdit={canEditForum(roles)}
        canModerate={canModerateForum(roles)}
      />
    </main>
  );
}
