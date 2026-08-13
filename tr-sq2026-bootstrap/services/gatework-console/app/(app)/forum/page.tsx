import { ForumStudio } from '@/components/forum-studio';
import { canEditForum, canModerateForum, canSeeForum, listForumCategories, type ForumCategory } from '@/lib/forum';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function ForumPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeForum(roles)) {
    return <main><h1 className="text-3xl font-semibold">Forum</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan forum yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  let categories: ForumCategory[] = [];
  let failure: string | null = null;
  try {
    categories = await listForumCategories();
  } catch (error) {
    failure = error instanceof Error ? error.message : 'Topluluk servisine ulaşılamadı.';
  }

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Community API bağlı operasyon</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Forum</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Uygulamadaki forum bölümleri buradan açılır, adlandırılır ve kapatılır; ana sayfadaki &quot;Forumda trend tartışmalar&quot; şeridi de aynı kayıtlardan beslenir. Her değişiklik gerekçesiyle birlikte denetim kaydına yazılır.
        </p>
      </div>

      {failure && <p className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Topluluk servisi yanıt vermedi: {failure}.</p>}

      <ForumStudio initialCategories={categories} canEdit={canEditForum(roles)} canModerate={canModerateForum(roles)} />
    </main>
  );
}
