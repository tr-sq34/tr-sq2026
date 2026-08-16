import { LegalDesk } from '@/components/legal/legal-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canDraftLegal, canPublishLegal, canSeeLegal, legalPage } from '@/lib/legal';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function LegalPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeLegal(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Yasal Metinler" />
        <EmptyState title="Bu alan içerik veya yönetim yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { documents, failure } = await legalPage();

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisi bağlı"
        title="Yasal Metinler"
        description="Giriş ekranının altında “Devam ederek Kullanım Koşulları ve Gizlilik Politikası'nı kabul etmiş olursunuz” yazıyor ve iki bağlantının da altı çiziliydi — ikisi de hiçbir yere gitmiyordu. Metinler artık burada yazılıyor ve buradan yayımlanıyor; yayımlanana kadar üyeye gitmiyor."
      />
      <LegalDesk
        initial={documents}
        initialFailure={failure}
        canDraft={canDraftLegal(roles)}
        canPublish={canPublishLegal(roles)}
      />
    </main>
  );
}
