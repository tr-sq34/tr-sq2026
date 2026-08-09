'use client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { MODERATION_ACTION_LABELS, type AuditRow, type ModeratedGroup, type RestrictionRow } from '@/lib/moderation-labels';

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

async function call(url: string, init: RequestInit) {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json' } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data;
}

export function MessagingOperations({ groups, restrictions, audit, canTakeDown, canAct }: {
  groups: ModeratedGroup[]; restrictions: RestrictionRow[]; audit: AuditRow[]; canTakeDown: boolean; canAct: boolean;
}) {
  const router = useRouter();
  const [tab, setTab] = useState<'groups' | 'restrictions' | 'audit'>('groups');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  // Both destructive actions ask for a written reason rather than a
  // confirmation dialog: the reason is what goes into the audit record, and an
  // operator who cannot articulate one should not be taking the action.
  async function run(id: string, prompt_: string, request: (reason: string) => Promise<unknown>) {
    const reason = window.prompt(prompt_)?.trim();
    if (!reason) return;
    if (reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı.'); return; }
    setBusy(id); setMessage(null);
    try {
      await request(reason);
      setMessage('İşlem tamamlandı.');
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İşlem tamamlanamadı.');
    } finally {
      setBusy(null);
    }
  }

  const tabs = [['groups', `Gruplar (${groups.length})`], ['restrictions', `Kısıtlamalar (${restrictions.length})`], ['audit', 'Denetim kaydı']] as const;

  return (
    <section>
      <div className="mb-4 flex gap-2">
        {tabs.map(([value, label]) => (
          <button key={value} type="button" onClick={() => setTab(value)} className={`rounded-lg px-3 py-1.5 text-xs font-medium ${tab === value ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300'}`}>{label}</button>
        ))}
      </div>

      {tab === 'groups' && (
        <div className="overflow-x-auto rounded-xl border border-white/10 bg-zinc-900/40">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-white/10 text-xs uppercase tracking-wide text-zinc-500">
              <tr><th className="p-3">Grup</th><th className="p-3">Kurucu</th><th className="p-3">Üye</th><th className="p-3">Açık şikâyet</th><th className="p-3">Son mesaj</th><th className="p-3" /></tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {groups.length === 0 && <tr><td colSpan={6} className="p-6 text-zinc-500">Henüz grup yok.</td></tr>}
              {groups.map((group) => (
                <tr key={group.id} className={group.removedAt ? 'opacity-50' : undefined}>
                  <td className="p-3">
                    <p className="text-zinc-200">{group.name}</p>
                    <p className="text-xs text-zinc-500">{group.city} · {group.privacy === 'public' ? 'herkese açık' : 'özel'}{group.removedAt && ` · kapatıldı: ${group.removedReason ?? ''}`}</p>
                  </td>
                  <td className="p-3 text-zinc-300">{group.ownerName ?? group.ownerId.slice(0, 8)}</td>
                  <td className="p-3 text-zinc-300">{group.memberCount}</td>
                  <td className="p-3">{group.openReports > 0 ? <span className="rounded bg-rose-500/20 px-2 py-0.5 text-xs text-rose-300">{group.openReports}</span> : <span className="text-zinc-600">0</span>}</td>
                  <td className="p-3 text-zinc-400">{time(group.lastMessageAt)}</td>
                  <td className="p-3 text-right">
                    {canTakeDown && !group.removedAt && (
                      <button type="button" disabled={busy === group.id}
                        onClick={() => void run(group.id, `"${group.name}" grubu kapatılacak. Gerekçe:`, (reason) => call(`/api/moderation/groups/${group.id}/takedown`, { method: 'POST', body: JSON.stringify({ reason }) }))}
                        className="rounded-lg border border-rose-500/40 px-3 py-1.5 text-xs text-rose-300 disabled:opacity-40">Grubu kapat</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'restrictions' && (
        <div className="overflow-x-auto rounded-xl border border-white/10 bg-zinc-900/40">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-white/10 text-xs uppercase tracking-wide text-zinc-500">
              <tr><th className="p-3">Kullanıcı</th><th className="p-3">Tür</th><th className="p-3">Bitiş</th><th className="p-3">Gerekçe</th><th className="p-3" /></tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {restrictions.length === 0 && <tr><td colSpan={5} className="p-6 text-zinc-500">Etkin kısıtlama yok.</td></tr>}
              {restrictions.map((row) => (
                <tr key={row.userId}>
                  <td className="p-3 text-zinc-200">{row.displayName ?? row.userId.slice(0, 8)}</td>
                  <td className="p-3 text-zinc-300">{row.restriction === 'suspended' ? 'Askıya alındı' : 'Susturuldu'}</td>
                  <td className="p-3 text-zinc-400">{row.expiresAt ? time(row.expiresAt) : 'süresiz'}</td>
                  <td className="max-w-md p-3 text-zinc-400">{row.reason}</td>
                  <td className="p-3 text-right">
                    {canAct && (
                      <button type="button" disabled={busy === row.userId}
                        onClick={() => void run(row.userId, 'Kısıtlama kaldırılacak. Gerekçe:', (reason) => call(`/api/moderation/restrictions/${row.userId}`, { method: 'DELETE', body: JSON.stringify({ reason }) }))}
                        className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40">Kaldır</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'audit' && (
        <div className="overflow-x-auto rounded-xl border border-white/10 bg-zinc-900/40">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-white/10 text-xs uppercase tracking-wide text-zinc-500">
              <tr><th className="p-3">Zaman</th><th className="p-3">İşlem</th><th className="p-3">Hedef</th><th className="p-3">Operatör</th><th className="p-3">Gerekçe</th></tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {audit.length === 0 && <tr><td colSpan={5} className="p-6 text-zinc-500">Henüz moderasyon işlemi yok.</td></tr>}
              {audit.map((row) => (
                <tr key={row.id}>
                  <td className="whitespace-nowrap p-3 text-zinc-400">{time(row.createdAt)}</td>
                  <td className="p-3 text-zinc-200">{MODERATION_ACTION_LABELS[row.action] ?? row.action}</td>
                  <td className="p-3 text-zinc-400">{row.targetType} · {row.targetId.slice(0, 8)}</td>
                  <td className="p-3 text-zinc-400">{row.actorId.slice(0, 8)} <span className="text-zinc-600">({row.actorRoles.join(', ')})</span></td>
                  <td className="max-w-md p-3 text-zinc-400">{row.reason}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {message && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-900 p-3 text-sm text-zinc-300">{message}</p>}
    </section>
  );
}
