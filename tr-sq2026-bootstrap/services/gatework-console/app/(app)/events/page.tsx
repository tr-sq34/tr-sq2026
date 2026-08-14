import { EventsDesk } from '@/components/events/events-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canPublishEvents, canSeeEvents, eventsPage } from '@/lib/events';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function EventsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeEvents(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Etkinlikler ve Biletleme" />
        <EmptyState title="Bu alan etkinlik yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { published, drafts, cancelled, failure } = await eventsPage();

  return (
    <main>
      <PageHeader
        eyebrow="Etkinlik bağlı · biletleme yapım aşamasında"
        tone="warning"
        title="Etkinlikler ve Biletleme"
        description="Uygulamadaki Etkinlikler sekmesi buradan doluyor. Yayınlanan bir etkinlik, tarihi geçene kadar üyelerin listesinde durur; iptal edilen kaybolmaz, gerekçesiyle görünür — o akşamı ayıran üyenin okuyacağı tek cümle odur. Kimlerin geldiği panele de gelmez, yalnızca sayısı. Bilet, QR ve bilet geliri henüz yok."
      />
      <EventsDesk
        initialPublished={published}
        initialDrafts={drafts}
        initialCancelled={cancelled}
        initialFailure={failure}
        canPublish={canPublishEvents(roles)}
      />
    </main>
  );
}
