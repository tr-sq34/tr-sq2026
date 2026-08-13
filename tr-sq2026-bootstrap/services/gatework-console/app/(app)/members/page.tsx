import { MemberConsole } from '@/components/member-console';
import { canManageRoles, canRestrictMembers, canRevokeSessions, canSeeMembers, canSetCapabilities, searchMembers, type IdentityMember } from '@/lib/members';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function MembersPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeMembers(roles)) {
    return <main><h1 className="text-3xl font-semibold">Üyeler</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan üye yönetimi yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  let members: IdentityMember[] = [];
  let failure: string | null = null;
  try {
    members = await searchMembers();
  } catch (error) {
    failure = error instanceof Error ? error.message : 'Kimlik servisine ulaşılamadı.';
  }

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Kimlik ve topluluk kayıtları birlikte</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Üyeler</h1>
        {/* Stated where the work happens: an operator opening this screen needs
            to know what it will not show them, before they go looking for it. */}
        <p className="mt-2 max-w-2xl text-zinc-400">
          Bir üye iki kayıttır: hesabı Kimlik servisinde, davranışı Topluluk servisinde durur. Bu ekran ikisini yan yana koyar. Parola, token veya özel mesaj hiçbir rolde görünmez; her rol değişikliği, kısıtlama ve oturum iptali gerekçesiyle birlikte denetim kaydına yazılır.
        </p>
      </div>

      {failure && <p className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Kimlik servisi yanıt vermedi: {failure}. Arama kutusu çalışmaya devam eder.</p>}

      <MemberConsole
        initialMembers={members}
        selfId={session.member.id}
        permissions={{
          manageRoles: canManageRoles(roles),
          revokeSessions: canRevokeSessions(roles),
          restrict: canRestrictMembers(roles),
          setCapabilities: canSetCapabilities(roles),
        }}
      />
    </main>
  );
}
