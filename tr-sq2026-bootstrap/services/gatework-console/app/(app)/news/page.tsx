import { NewsDesk } from '@/components/content/news-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canPublishContent, canSeeNews, listNewsArticles, listSystemAccounts, type NewsSummary, type SystemAccount } from '@/lib/content';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function NewsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeNews(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Haber Merkezi" />
        <EmptyState title="Bu alan haber yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  // Two independent reads. The publish form needs the accounts and the list
  // needs the articles; one failing must not take the other down, because an
  // editor who cannot list yesterday's pieces can still write today's.
  const [articles, accounts] = await Promise.all([
    listNewsArticles().catch((error: unknown) => (error instanceof Error ? error : new Error('Haber listesi okunamadı.'))),
    listSystemAccounts().catch(() => [] as SystemAccount[]),
  ]);

  const failed = articles instanceof Error;

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="Haber Merkezi"
        description="Uygulamadaki Haber Merkezi ve ana sayfadaki manşet şeridi aynı kayıttan beslenir; manşet sırası alanı ikincisini belirler. Metin uygulamada düz paragraf olarak çizilir — sağdaki önizleme paragrafların nerede bölüneceğini yazdıkça gösterir."
      />
      <NewsDesk
        initialArticles={failed ? [] : (articles as NewsSummary[])}
        accounts={accounts}
        loadFailure={failed ? `Haber listesi okunamadı: ${(articles as Error).message}.` : null}
        canPublish={canPublishContent(roles)}
      />
    </main>
  );
}
