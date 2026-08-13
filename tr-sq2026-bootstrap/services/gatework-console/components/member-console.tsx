'use client';
import { useCallback, useEffect, useState } from 'react';
import { gateworkRoles, type GateworkRole } from '@/lib/types';
import { RESTRICTION_LABELS, ROLE_HINTS, ROLE_LABELS, type CommunityMember, type IdentityMember } from '@/lib/member-labels';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data as T;
}

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

export type MemberPermissions = {
  manageRoles: boolean;
  revokeSessions: boolean;
  restrict: boolean;
  setCapabilities: boolean;
};

export function MemberConsole({ initialMembers, permissions, selfId }: { initialMembers: IdentityMember[]; permissions: MemberPermissions; selfId: string }) {
  const [members, setMembers] = useState(initialMembers);
  const [query, setQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [selected, setSelected] = useState<IdentityMember | null>(initialMembers[0] ?? null);
  const [community, setCommunity] = useState<CommunityMember | null>(null);
  const [communityError, setCommunityError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const search = useCallback(async (nextQuery: string, nextRole: string) => {
    setMessage(null);
    try {
      const params = new URLSearchParams();
      if (nextQuery.trim().length >= 2) params.set('query', nextQuery.trim());
      if (nextRole) params.set('role', nextRole);
      const rows = await call<IdentityMember[]>(`/api/members?${params}`);
      setMembers(rows);
      setSelected(rows[0] ?? null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Arama başarısız.');
    }
  }, []);

  // Community is asked separately and is allowed to fail on its own: an account
  // that has never posted, or a service mid-deploy, must still leave the
  // identity half of the screen usable.
  useEffect(() => {
    if (!selected) { setCommunity(null); return; }
    let active = true;
    setCommunity(null); setCommunityError(null);
    call<CommunityMember>(`/api/members/${selected.id}`)
      .then((row) => { if (active) setCommunity(row); })
      .catch((error: unknown) => { if (active) setCommunityError(error instanceof Error ? error.message : 'Topluluk bilgisi alınamadı.'); });
    return () => { active = false; };
  }, [selected]);

  async function refreshSelected() {
    if (!selected) return;
    const rows = await call<IdentityMember[]>(`/api/members?query=${encodeURIComponent(selected.email)}`).catch(() => null);
    if (!rows) return;
    setMembers((current) => current.map((row) => rows.find((fresh) => fresh.id === row.id) ?? row));
    const fresh = rows.find((row) => row.id === selected.id);
    if (fresh) setSelected(fresh);
  }

  async function run(action: () => Promise<unknown>, done: string) {
    setBusy(true); setMessage(null);
    try {
      await action();
      setMessage(done);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İşlem tamamlanamadı.');
    } finally {
      setBusy(false);
    }
  }

  // Every mutation asks for a sentence first. The services refuse a reason
  // shorter than five characters, so a rushed "ok" fails here rather than after
  // a round trip.
  function reasonFor(prompt_: string) {
    const reason = window.prompt(`${prompt_}\n\nGerekçe (denetim kaydına yazılır, en az 5 karakter):`)?.trim();
    if (!reason || reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı; işlem yapılmadı.'); return null; }
    return reason;
  }

  async function toggleRole(role: GateworkRole, held: boolean) {
    if (!selected) return;
    const reason = reasonFor(held ? `${selected.email} hesabından "${ROLE_LABELS[role]}" rolü kaldırılacak.` : `${selected.email} hesabına "${ROLE_LABELS[role]}" rolü verilecek.`);
    if (!reason) return;
    await run(async () => {
      await call(`/api/members/${selected.id}/roles`, { method: held ? 'DELETE' : 'POST', body: JSON.stringify({ role, reason }) });
      await refreshSelected();
    }, held ? 'Rol kaldırıldı.' : 'Rol verildi.');
  }

  async function restrict(form: FormData) {
    if (!selected) return;
    const durationRaw = String(form.get('durationHours') ?? '');
    await run(async () => {
      await call(`/api/members/${selected.id}/restrictions`, {
        method: 'POST',
        body: JSON.stringify({
          kind: form.get('kind'),
          reason: form.get('reason'),
          // Empty means indefinite, which is a different decision from "one
          // hour" and must not silently become a number.
          durationHours: durationRaw ? Number(durationRaw) : undefined,
        }),
      });
      setCommunity(await call<CommunityMember>(`/api/members/${selected.id}`));
    }, 'Kısıtlama uygulandı.');
  }

  const field = 'mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  const secondary = 'rounded-lg bg-zinc-800 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40';

  return (
    <section className="grid gap-6 xl:grid-cols-[380px_1fr]">
      <div className="rounded-xl border border-white/10 bg-zinc-900/40">
        <form
          className="grid gap-2 border-b border-white/10 p-3"
          onSubmit={(event) => { event.preventDefault(); void search(query, roleFilter); }}
        >
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="E-posta veya ad ara (en az 2 harf)" className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400" />
          <div className="flex gap-2">
            <select value={roleFilter} onChange={(event) => setRoleFilter(event.target.value)} className="min-w-0 flex-1 rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400">
              <option value="">Tüm üyeler</option>
              {gateworkRoles.map((role) => <option key={role} value={role}>{ROLE_LABELS[role]}</option>)}
            </select>
            <button className="rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950">Ara</button>
          </div>
        </form>
        <ul className="max-h-[70vh] divide-y divide-white/5 overflow-y-auto">
          {members.length === 0 && <li className="p-6 text-sm text-zinc-500">Bu filtrede üye yok.</li>}
          {members.map((member) => (
            <li key={member.id}>
              <button type="button" onClick={() => setSelected(member)} className={`w-full px-4 py-3 text-left transition ${selected?.id === member.id ? 'bg-zinc-800' : 'hover:bg-zinc-800/50'}`}>
                <p className="truncate text-sm text-zinc-200">{member.displayName}</p>
                <p className="truncate text-xs text-zinc-500">{member.email}</p>
                <p className="mt-1 truncate text-[11px] text-emerald-400">{member.roles.length ? member.roles.join(' · ') : 'panel yetkisi yok'}</p>
              </button>
            </li>
          ))}
        </ul>
      </div>

      <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-6">
        {!selected && <p className="text-sm text-zinc-500">Soldan bir üye seç.</p>}
        {selected && (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <h2 className="text-xl font-semibold">{selected.displayName}</h2>
              {!selected.emailVerified && <span className="rounded bg-amber-500/20 px-2 py-0.5 text-xs text-amber-200">E-posta doğrulanmamış</span>}
              {selected.id === selfId && <span className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-300">Bu sensin</span>}
              {community?.restriction && <span className="rounded bg-rose-500/20 px-2 py-0.5 text-xs text-rose-300">{RESTRICTION_LABELS[community.restriction.kind] ?? community.restriction.kind}</span>}
            </div>
            <dl className="mt-4 grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2">
              <div><dt className="text-zinc-500">E-posta</dt><dd className="text-zinc-200">{selected.email}</dd></div>
              <div><dt className="text-zinc-500">Kayıt</dt><dd className="text-zinc-200">{time(selected.createdAt)}</dd></div>
              <div><dt className="text-zinc-500">Şehir</dt><dd className="text-zinc-200">{community?.city ?? '—'}{community?.regionCode ? `, ${community.regionCode}` : ''}</dd></div>
              <div><dt className="text-zinc-500">Kimlik doğrulaması</dt><dd className="text-zinc-200">{community?.identityVerified ? 'Doğrulanmış' : 'Yok'}</dd></div>
            </dl>

            {communityError && <p className="mt-4 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-200">Topluluk servisi yanıt vermedi: {communityError}</p>}
            {community && (
              <>
                <div className="mt-6 grid gap-3 sm:grid-cols-3">
                  {([
                    ['Paylaşım', `${community.activity.posts} akış · ${community.activity.comments} yorum`],
                    ['Forum', `${community.activity.forumTopics} konu · ${community.activity.forumReplies} yanıt`],
                    ['Çarşı', `${community.activity.listings} ilan`],
                  ] as const).map(([title, value]) => (
                    <article key={title} className="rounded-lg border border-white/10 bg-zinc-950/40 p-4">
                      <p className="text-xs text-zinc-500">{title}</p>
                      <p className="mt-1 text-sm text-zinc-200">{value}</p>
                    </article>
                  ))}
                </div>
                {/* One report says almost nothing; "kaç kere, kaçı haklı" is the
                    number a proportionate decision needs. */}
                <p className={`mt-3 rounded-lg border p-3 text-sm ${community.reports.upheld > 0 ? 'border-rose-500/30 bg-rose-500/10 text-rose-200' : 'border-white/10 bg-zinc-950/40 text-zinc-300'}`}>
                  Hakkında {community.reports.filedAgainst} şikâyet · {community.reports.upheld} tanesi haklı bulundu · {community.reports.open} tanesi kuyrukta
                </p>
                {community.restriction && (
                  <div className="mt-3 rounded-lg border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200">
                    <p>{RESTRICTION_LABELS[community.restriction.kind] ?? community.restriction.kind} · {community.restriction.reason}</p>
                    <p className="mt-1 text-xs">{community.restriction.expiresAt ? `Bitiş: ${time(community.restriction.expiresAt)}` : 'Süresiz'}</p>
                    {permissions.restrict && (
                      <button
                        type="button"
                        disabled={busy}
                        className="mt-2 rounded-lg bg-zinc-900 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40"
                        onClick={() => {
                          const reason = reasonFor('Kısıtlama kaldırılacak.');
                          if (!reason) return;
                          void run(async () => {
                            await call(`/api/members/${selected.id}/restrictions`, { method: 'DELETE', body: JSON.stringify({ reason }) });
                            setCommunity(await call<CommunityMember>(`/api/members/${selected.id}`));
                          }, 'Kısıtlama kaldırıldı.');
                        }}
                      >
                        Kısıtlamayı kaldır
                      </button>
                    )}
                  </div>
                )}
              </>
            )}

            <h3 className="mt-6 text-sm font-semibold text-zinc-300">Panel rolleri</h3>
            <ul className="mt-2 grid gap-2">
              {gateworkRoles.map((role) => {
                const held = selected.roles.includes(role);
                return (
                  <li key={role} className="flex items-center justify-between gap-4 rounded-lg border border-white/10 bg-zinc-950/40 px-3 py-2">
                    <div className="min-w-0">
                      <p className={`text-sm ${held ? 'text-emerald-300' : 'text-zinc-300'}`}>{ROLE_LABELS[role]}</p>
                      <p className="truncate text-xs text-zinc-500">{ROLE_HINTS[role]}</p>
                    </div>
                    {permissions.manageRoles
                      ? <button type="button" disabled={busy} onClick={() => void toggleRole(role, held)} className={held ? 'rounded-lg bg-rose-500/20 px-3 py-1.5 text-xs text-rose-200 disabled:opacity-40' : secondary}>{held ? 'Kaldır' : 'Ver'}</button>
                      : <span className="text-xs text-zinc-500">{held ? 'var' : '—'}</span>}
                  </li>
                );
              })}
            </ul>
            {!permissions.manageRoles && <p className="mt-2 text-xs text-zinc-500">Rol vermek ve kaldırmak yalnızca Owner rolüne açıktır.</p>}

            {permissions.setCapabilities && community && (
              <div className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
                <h3 className="font-semibold">İhale satıcı yetkisi</h3>
                {/* The badge itself is not settable here: the console must not be
                    able to declare a document checked that nobody checked. */}
                <p className="mt-1 text-sm text-zinc-400">Onaylı Hesap rozeti doğrulama sağlayıcısından gelir ve buradan değiştirilemez. Buradaki karar, doğrulanmış hesabın ihale açabilmesidir.</p>
                <button
                  type="button"
                  disabled={busy}
                  className="mt-3 rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40"
                  onClick={() => {
                    const next = !community.auctionSellerEligible;
                    const reason = reasonFor(next ? 'Üyeye ihale açma yetkisi verilecek.' : 'Üyenin ihale açma yetkisi kaldırılacak.');
                    if (!reason) return;
                    void run(async () => {
                      await call(`/api/members/${selected.id}/capabilities`, { method: 'PUT', body: JSON.stringify({ auctionSellerEligible: next, reason }) });
                      setCommunity({ ...community, auctionSellerEligible: next });
                    }, next ? 'Yetki verildi.' : 'Yetki kaldırıldı.');
                  }}
                >
                  {community.auctionSellerEligible ? 'İhale yetkisini kaldır' : 'İhale yetkisi ver'}
                </button>
              </div>
            )}

            {permissions.restrict && !community?.restriction && (
              <form action={restrict} className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
                <h3 className="font-semibold">Kısıtla</h3>
                <p className="mt-1 text-sm text-zinc-400">Şikâyet beklemeden uygulanır; karar aynı denetim kaydına yazılır.</p>
                <div className="mt-4 grid gap-4 sm:grid-cols-2">
                  <label className="block text-sm">Tür
                    <select name="kind" className={field} defaultValue="muted">
                      <option value="muted">Susturma (paylaşamaz, okuyabilir)</option>
                      <option value="suspended">Askıya alma</option>
                    </select>
                  </label>
                  <label className="block text-sm">Süre (saat) <span className="text-zinc-600">boş = süresiz</span>
                    <input name="durationHours" type="number" min={1} max={8760} className={field} placeholder="24" />
                  </label>
                </div>
                <label className="mt-4 block text-sm">Gerekçe <span className="text-zinc-600">(denetim kaydına yazılır)</span>
                  <textarea name="reason" required minLength={5} maxLength={500} rows={3} className={field} />
                </label>
                <button disabled={busy} className="mt-4 rounded-lg bg-rose-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">Kısıtlamayı uygula</button>
              </form>
            )}

            {permissions.revokeSessions && selected.id !== selfId && (
              <div className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
                <h3 className="font-semibold">Oturumlar</h3>
                <p className="mt-1 text-sm text-zinc-400">Hesabın tüm cihazlardaki oturumu kapatılır; üye yeniden giriş yapmak zorunda kalır. Parola değiştirilmez, gösterilmez.</p>
                <button
                  type="button"
                  disabled={busy}
                  className={`mt-3 ${secondary}`}
                  onClick={() => {
                    const reason = reasonFor(`${selected.email} hesabının tüm oturumları kapatılacak.`);
                    if (!reason) return;
                    void run(() => call(`/api/members/${selected.id}/sessions`, { method: 'DELETE', body: JSON.stringify({ reason }) }), 'Oturumlar kapatıldı.');
                  }}
                >
                  Tüm oturumları kapat
                </button>
              </div>
            )}
          </>
        )}
        {message && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-900 p-3 text-sm text-zinc-300">{message}</p>}
      </div>
    </section>
  );
}
