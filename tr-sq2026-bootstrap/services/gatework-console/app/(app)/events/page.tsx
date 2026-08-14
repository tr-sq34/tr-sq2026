import { EventsDesk } from '@/components/events-desk';
import { canPublishEvents, canSeeEvents, eventsPage } from '@/lib/events';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function EventsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeEvents(roles)) {
    return <main><h1 className="text-3xl font-semibold">Etkinlikler</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan etkinlik yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  const { published, drafts, cancelled, failure } = await eventsPage();

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Community API bağlı operasyon</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Etkinlikler</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Uygulamadaki Etkinlikler sekmesi buradan doluyor. Yayınlanan bir etkinlik, tarihi geçene kadar üyelerin listesinde durur; iptal edilen kaybolmaz, gerekçesiyle görünür — o akşamı ayıran üyenin okuyacağı tek cümle odur. Kimlerin geldiği panele de gelmez, yalnızca sayısı.
        </p>
      </div>

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
