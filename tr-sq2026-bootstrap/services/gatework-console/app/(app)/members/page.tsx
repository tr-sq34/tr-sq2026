import { MemberDesk } from '@/components/members/member-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canSeeAudit } from '@/lib/audit';
import { canManageRoles, canRestrictMembers, canRevokeSessions, canSeeMembers, canSetCapabilities, searchMembers, type IdentityMember } from '@/lib/members';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function MembersPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeMembers(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Üyeler" />
        <EmptyState
          title="Bu alan üye yönetimi yetkisi gerektirir."
          description={`Mevcut rollerin: ${roles.join(', ')}.`}
        />
      </main>
    );
  }

  // The first page is fetched on the server so the table has rows before any
  // JavaScript runs; failing here must not blank the screen, because the search
  // box is what an operator came for.
  let members: IdentityMember[] = [];
  let failure: string | null = null;
  try {
    members = await searchMembers();
  } catch (error) {
    failure = `Kimlik servisi yanıt vermedi: ${error instanceof Error ? error.message : 'bilinmeyen hata'}.`;
  }

  return (
    <main>
      <PageHeader
        eyebrow="Kimlik ve topluluk kayıtları birlikte"
        title="Üyeler"
        description="Bir üye iki kayıttır: hesabı Kimlik servisinde, davranışı Topluluk servisinde durur. Bu ekran ikisini yan yana koyar. Parola, jeton veya özel mesaj hiçbir rolde görünmez; her rol değişikliği, kısıtlama ve oturum iptali gerekçesiyle birlikte denetim kaydına yazılır."
      />
      <MemberDesk
        initialMembers={members}
        selfId={session.member.id}
        loadFailure={failure}
        permissions={{
          manageRoles: canManageRoles(roles),
          revokeSessions: canRevokeSessions(roles),
          restrict: canRestrictMembers(roles),
          setCapabilities: canSetCapabilities(roles),
          seeAudit: canSeeAudit(roles),
        }}
      />
    </main>
  );
}
