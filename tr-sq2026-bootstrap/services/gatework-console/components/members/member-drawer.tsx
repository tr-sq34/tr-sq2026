'use client';
import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Ban, Gavel, LogOut, ShieldCheck } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import { actionLabel, OUTCOME_LABELS, SERVICE_LABELS, type AuditRow } from '@/lib/audit-labels';
import {
  deviceLabel,
  RESTRICTION_LABELS,
  ROLE_HINTS,
  ROLE_LABELS,
  type CommunityMember,
  type IdentityMember,
  type MemberPermissions,
  type MemberSession,
} from '@/lib/member-labels';
import { gateworkRoles, type GateworkRole } from '@/lib/types';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState, NotConnected } from '@/components/ui/page';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

/**
 * One member, four tabs.
 *
 * The screen this replaces put everything in a single scrolling column: account
 * facts, activity counts, seven role rows, a restriction form and a session
 * kill switch. An operator answering "why is this account muted" scrolled past
 * the destructive controls twice to get there. Splitting it means each tab
 * answers one question, and the two tabs that can end someone's access are the
 * ones you have to choose deliberately.
 *
 * Identity and Community are asked separately and are allowed to fail
 * separately. The account half comes from the row already in the table, so a
 * Community outage leaves the drawer usable rather than empty.
 */
type Pending =
  | { kind: 'role'; role: GateworkRole; held: boolean }
  | { kind: 'lift' }
  | { kind: 'capability'; next: boolean }
  | { kind: 'sessions' }
  | null;

function Row({ label, value, tone }: { label: string; value: React.ReactNode; tone?: 'muted' }) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b border-hairline/60 py-2.5 last:border-0">
      <span className="shrink-0 text-xs text-ink-faint">{label}</span>
      <span className={tone === 'muted' ? 'text-right text-sm text-ink-faint' : 'text-right text-sm text-ink'}>{value}</span>
    </div>
  );
}

function Notice({ tone, children }: { tone: 'warning' | 'danger' | 'neutral'; children: React.ReactNode }) {
  const skin =
    tone === 'danger'
      ? 'border-danger/40 bg-danger-soft text-danger'
      : tone === 'warning'
        ? 'border-warning/30 bg-warning-soft text-warning'
        : 'border-hairline bg-surface-raised text-ink-muted';
  return <div className={`rounded-card border p-3.5 text-sm ${skin}`}>{children}</div>;
}

export function MemberDrawer({
  member,
  permissions,
  selfId,
  onIdentityChanged,
}: {
  member: IdentityMember;
  permissions: MemberPermissions;
  selfId: string;
  onIdentityChanged: () => Promise<void>;
}) {
  const [community, setCommunity] = useState<CommunityMember | null>(null);
  const [communityError, setCommunityError] = useState<string | null>(null);
  const [pending, setPending] = useState<Pending>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // Oturumlar kapatildiktan sonra listenin eski halini gostermek, islemin
  // yapilmadigi izlenimini birakiyor. Sayaci artirmak listeyi yeniden sordurur.
  const [sessionsVersion, setSessionsVersion] = useState(0);

  const loadCommunity = useCallback(async () => {
    setCommunityError(null);
    try {
      setCommunity(await apiData<CommunityMember>(`/api/members/${member.id}`));
    } catch (error) {
      setCommunityError(errorText(error, 'Topluluk bilgisi alınamadı.'));
    }
  }, [member.id]);

  useEffect(() => { void loadCommunity(); }, [loadCommunity]);

  const isSelf = member.id === selfId;

  async function confirm(reason: string) {
    if (!pending) return;
    if (pending.kind === 'role') {
      await apiData(`/api/members/${member.id}/roles`, {
        method: pending.held ? 'DELETE' : 'POST',
        body: JSON.stringify({ role: pending.role, reason }),
      });
      await onIdentityChanged();
      setNotice(pending.held ? 'Rol kaldırıldı.' : 'Rol verildi.');
    } else if (pending.kind === 'lift') {
      await apiData(`/api/members/${member.id}/restrictions`, { method: 'DELETE', body: JSON.stringify({ reason }) });
      await loadCommunity();
      setNotice('Kısıtlama kaldırıldı.');
    } else if (pending.kind === 'capability') {
      await apiData(`/api/members/${member.id}/capabilities`, {
        method: 'PUT',
        body: JSON.stringify({ auctionSellerEligible: pending.next, reason }),
      });
      await loadCommunity();
      setNotice(pending.next ? 'İhale açma yetkisi verildi.' : 'İhale açma yetkisi kaldırıldı.');
    } else if (pending.kind === 'sessions') {
      await apiData(`/api/members/${member.id}/sessions`, { method: 'DELETE', body: JSON.stringify({ reason }) });
      setSessionsVersion((version) => version + 1);
      setNotice('Tüm oturumlar kapatıldı; üye yeniden giriş yapmak zorunda.');
    }
  }

  const dialogCopy = (): { title: string; description: string; confirmLabel: string; variant: 'primary' | 'danger' } => {
    if (pending?.kind === 'role') {
      return pending.held
        ? { title: 'Rol kaldırılacak', description: `${member.email} hesabından "${ROLE_LABELS[pending.role]}" yetkisi alınıyor.`, confirmLabel: 'Rolü kaldır', variant: 'danger' }
        : { title: 'Rol verilecek', description: `${member.email} hesabına "${ROLE_LABELS[pending.role]}" yetkisi veriliyor.`, confirmLabel: 'Rolü ver', variant: 'primary' };
    }
    if (pending?.kind === 'lift') return { title: 'Kısıtlama kaldırılacak', description: `${member.displayName} yeniden paylaşım yapabilecek.`, confirmLabel: 'Kısıtlamayı kaldır', variant: 'primary' };
    if (pending?.kind === 'capability') {
      return pending.next
        ? { title: 'İhale yetkisi verilecek', description: `${member.displayName} ihale açabilecek.`, confirmLabel: 'Yetki ver', variant: 'primary' }
        : { title: 'İhale yetkisi kaldırılacak', description: `${member.displayName} yeni ihale açamayacak.`, confirmLabel: 'Yetkiyi kaldır', variant: 'danger' };
    }
    return { title: 'Tüm oturumlar kapatılacak', description: `${member.email} hesabı her cihazda çıkış yapar. Parola değişmez.`, confirmLabel: 'Oturumları kapat', variant: 'danger' };
  };

  return (
    <div className="p-5">
      {notice && <Notice tone="neutral">{notice}</Notice>}
      {communityError && (
        <div className="mb-4">
          <Notice tone="warning">
            Topluluk servisi yanıt vermedi: {communityError}
            <br />
            <span className="text-xs">Hesap bilgileri Kimlik servisinden geldiği için görünmeye devam ediyor; davranış ve ceza verileri eksik.</span>
          </Notice>
        </div>
      )}

      <Tabs defaultValue="overview" className={notice ? 'mt-4' : undefined}>
        <TabsList className="mb-5 w-full">
          <TabsTrigger value="overview">Genel</TabsTrigger>
          <TabsTrigger value="finance">Çip &amp; Finans</TabsTrigger>
          <TabsTrigger value="roles" count={member.roles.length}>Roller &amp; Cezalar</TabsTrigger>
          <TabsTrigger value="sessions">Oturumlar</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">
          <OverviewTab member={member} community={community} isSelf={isSelf} />
        </TabsContent>

        <TabsContent value="finance">
          <FinanceTab />
        </TabsContent>

        <TabsContent value="roles">
          <RolesTab
            member={member}
            community={community}
            permissions={permissions}
            busy={busy}
            setBusy={setBusy}
            setNotice={setNotice}
            reloadCommunity={loadCommunity}
            onAsk={setPending}
          />
        </TabsContent>

        <TabsContent value="sessions">
          <SessionsTab
            member={member}
            permissions={permissions}
            isSelf={isSelf}
            reloadToken={sessionsVersion}
            onAsk={() => setPending({ kind: 'sessions' })}
          />
        </TabsContent>
      </Tabs>

      <ReasonDialog
        open={pending !== null}
        onOpenChange={(open) => { if (!open) setPending(null); }}
        {...dialogCopy()}
        onConfirm={confirm}
      />
    </div>
  );
}

function OverviewTab({ member, community, isSelf }: { member: IdentityMember; community: CommunityMember | null; isSelf: boolean }) {
  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap gap-2">
        {isSelf && <Badge>Bu sensin</Badge>}
        {member.emailVerified ? <Badge tone="success" dot>E-posta doğrulandı</Badge> : <Badge tone="warning" dot>E-posta doğrulanmadı</Badge>}
        {community?.identityVerified && <Badge tone="brand" dot>Kimliği doğrulanmış</Badge>}
        {community?.restriction && <Badge tone="danger" dot>{RESTRICTION_LABELS[community.restriction.kind] ?? community.restriction.kind}</Badge>}
      </div>

      <Card>
        <CardContent className="py-1">
          <Row label="E-posta" value={member.email} />
          <Row label="Kayıt" value={formatDateTime(member.createdAt)} />
          <Row label="Şehir" value={community ? [community.city, community.regionCode].filter(Boolean).join(', ') || '—' : '—'} />
          <Row label="Geldiği ülke" value={community?.originCountry ?? '—'} />
          <Row label="Hesap kimliği" value={<code className="text-xs text-ink-faint">{member.id}</code>} />
        </CardContent>
      </Card>

      {community && (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {([
              ['Akış paylaşımı', community.activity.posts],
              ['Yorum', community.activity.comments],
              ['Forum konusu', community.activity.forumTopics],
              ['Forum yanıtı', community.activity.forumReplies],
              ['Çarşı ilanı', community.activity.listings],
            ] as const).map(([label, value]) => (
              <Card key={label} tone="raised">
                <div className="p-4">
                  <p className="text-xs text-ink-faint">{label}</p>
                  <p className="mt-1 text-xl font-semibold text-ink">{value}</p>
                </div>
              </Card>
            ))}
          </div>

          {/* One report says almost nothing. "Kaç kere ve kaçı haklı" is the
              number a proportionate decision needs, so the three counts stay
              together and never appear alone. */}
          <Notice tone={community.reports.upheld > 0 ? 'danger' : 'neutral'}>
            Hakkında <strong>{community.reports.filedAgainst}</strong> şikâyet ·{' '}
            <strong>{community.reports.upheld}</strong> tanesi haklı bulundu ·{' '}
            <strong>{community.reports.open}</strong> tanesi hâlâ kuyrukta
          </Notice>
        </>
      )}
    </div>
  );
}

function FinanceTab() {
  return (
    <div className="grid gap-4">
      <NotConnected
        what="Çip bakiyesi ve işlem geçmişi"
        why="Uygulamada çip/cüzdan sistemi henüz yok: bakiye tutan bir tablo, para hareketi yazan bir servis ve bunu okuyacak bir uç nokta bulunmuyor. Burada bir sayı göstermek için onu uydurmak gerekirdi."
      />
      <NotConnected
        what="Biletlerim — QR kod durumları ve bilet geliri"
        why="Etkinlik ve biletleme modülü yapım aşamasında bırakıldı. Bilet sağlayıcısı seçimi ve QR doğrulama akışı netleşmeden buraya gelir rakamı yazılmayacak."
      />
    </div>
  );
}

function RolesTab({
  member, community, permissions, busy, setBusy, setNotice, reloadCommunity, onAsk,
}: {
  member: IdentityMember;
  community: CommunityMember | null;
  permissions: MemberPermissions;
  busy: boolean;
  setBusy: (value: boolean) => void;
  setNotice: (value: string | null) => void;
  reloadCommunity: () => Promise<void>;
  onAsk: (pending: Pending) => void;
}) {
  const [kind, setKind] = useState('muted');
  const [hours, setHours] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function applyRestriction(event: React.FormEvent) {
    event.preventDefault();
    if (reason.trim().length < 5) { setError('Gerekçe en az 5 karakter olmalı.'); return; }
    setBusy(true); setError(null);
    try {
      await apiData(`/api/members/${member.id}/restrictions`, {
        method: 'POST',
        body: JSON.stringify({
          kind,
          reason: reason.trim(),
          // Empty is indefinite, which is a different decision from "one hour"
          // and must not quietly become a number.
          durationHours: hours ? Number(hours) : undefined,
        }),
      });
      await reloadCommunity();
      setReason(''); setHours('');
      setNotice('Kısıtlama uygulandı.');
    } catch (caught) {
      setError(errorText(caught, 'Kısıtlama uygulanamadı.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-4">
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Panel rolleri</CardTitle>
            <CardDescription>Her anahtar tek bir yetkiyi değiştirir ve tek bir denetim kaydı yazar.</CardDescription>
          </div>
          <ShieldCheck size={16} className="shrink-0 text-ink-faint" />
        </CardHeader>
        <CardContent className="divide-y divide-hairline/60 py-1">
          {gateworkRoles.map((role) => {
            const held = member.roles.includes(role);
            return (
              <Switch
                key={role}
                label={ROLE_LABELS[role]}
                hint={ROLE_HINTS[role]}
                checked={held}
                disabled={!permissions.manageRoles || busy}
                // Nothing changes here: the switch stays where it is until the
                // service confirms, so a cancelled dialog cannot leave the
                // screen claiming a grant that never happened.
                onCheckedChange={() => onAsk({ kind: 'role', role, held })}
              />
            );
          })}
        </CardContent>
        {!permissions.manageRoles && (
          <div className="border-t border-hairline px-5 py-3 text-xs text-ink-faint">
            Rol vermek ve kaldırmak yalnızca Sahip rolüne açıktır.
          </div>
        )}
      </Card>

      {community?.restriction ? (
        <Card tone="urgent">
          <CardContent>
            <div className="flex items-start gap-3">
              <Ban size={16} className="mt-0.5 shrink-0 text-danger" />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-danger">{RESTRICTION_LABELS[community.restriction.kind] ?? community.restriction.kind}</p>
                <p className="mt-1 text-sm text-ink-muted">{community.restriction.reason}</p>
                <p className="mt-1.5 text-xs text-ink-faint">
                  {community.restriction.expiresAt ? `Bitiş: ${formatDateTime(community.restriction.expiresAt)}` : 'Süresiz'}
                </p>
                {permissions.restrict && (
                  <Button size="sm" variant="outline" disabled={busy} className="mt-3" onClick={() => onAsk({ kind: 'lift' })}>
                    Kısıtlamayı kaldır
                  </Button>
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      ) : permissions.restrict ? (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Kısıtla</CardTitle>
              <CardDescription>Şikâyet beklemeden uygulanır; karar aynı denetim kaydına yazılır.</CardDescription>
            </div>
            <AlertTriangle size={16} className="shrink-0 text-warning" />
          </CardHeader>
          <CardContent>
            <form onSubmit={applyRestriction} className="grid gap-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Tür">
                  <Select value={kind} onChange={(event) => setKind(event.target.value)}>
                    <option value="muted">Susturma — okuyabilir, paylaşamaz</option>
                    <option value="suspended">Askıya alma</option>
                  </Select>
                </Field>
                <Field label="Süre (saat)" hint="Boş bırakırsan süresiz olur.">
                  <Input type="number" min={1} max={8760} placeholder="24" value={hours} onChange={(event) => setHours(event.target.value)} />
                </Field>
              </div>
              <Field label="Gerekçe" error={error ?? undefined} hint="Denetim kaydına aynen yazılır.">
                <Textarea rows={3} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
              </Field>
              <div>
                <Button type="submit" variant="danger" disabled={busy}>
                  {busy ? 'Uygulanıyor…' : 'Kısıtlamayı uygula'}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      ) : null}

      {permissions.setCapabilities && community && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>İhale satıcı yetkisi</CardTitle>
              {/* The verification badge itself is not settable here: the console
                  must not be able to declare a document checked that nobody
                  checked. */}
              <CardDescription>
                Onaylı Hesap rozeti doğrulama sağlayıcısından gelir, buradan değiştirilemez. Buradaki karar yalnızca doğrulanmış hesabın ihale açabilmesidir.
              </CardDescription>
            </div>
            <Gavel size={16} className="shrink-0 text-ink-faint" />
          </CardHeader>
          <CardContent className="py-1">
            <Switch
              label="İhale açabilir"
              hint={community.identityVerified ? 'Hesabın kimliği doğrulanmış.' : 'Hesabın kimliği doğrulanmamış — yetki vermeden önce doğrulama beklenir.'}
              checked={community.auctionSellerEligible}
              disabled={busy}
              onCheckedChange={(next) => onAsk({ kind: 'capability', next })}
            />
          </CardContent>
        </Card>
      )}
    </div>
  );
}

/**
 * Bu hesabin acik oturumlari: her satir bir yenileme jetonu ailesi, yani bir
 * cihazdaki bir giris.
 *
 * Uc alan da eksik olabiliyor ve hicbiri tahminle doldurulmuyor. Cihaz imzasi
 * gelmemisse "Cihaz bilgisi gelmedi" yaziyor; ag blogu yoksa satirda yer
 * kaplamiyor. Adres zaten tam haliyle saklanmiyor - kimlik servisi yalnizca
 * /24 (IPv6'da /48) blogunu yaziyor - dolayisiyla panelde de o kadari var.
 *
 * Liste sondan bir onceki soruyu cevaplamiyor: "bu oturum su an calisiyor mu".
 * Ailenin jetonlarinin en gec bitis tarihi gecmisse satir "suresi dolmus"
 * olarak isaretleniyor; asil kapatma islemi yukaridaki dugmede.
 */
function SessionList({
  member, permissions, reloadToken,
}: {
  member: IdentityMember;
  permissions: MemberPermissions;
  reloadToken: number;
}) {
  const [sessions, setSessions] = useState<MemberSession[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!permissions.seeAudit) return;
    let active = true;
    setSessions(null);
    setError(null);
    (async () => {
      try {
        const data = await apiData<MemberSession[]>(`/api/members/${member.id}/sessions`);
        if (active) setSessions(data);
      } catch (caught) {
        if (active) setError(errorText(caught, 'Oturum listesi alınamadı.'));
      }
    })();
    return () => { active = false; };
  }, [member.id, permissions.seeAudit, reloadToken]);

  const now = Date.now();

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Açık oturumlar</CardTitle>
          <CardDescription>
            Her satır bir cihazdaki bir giriş. Tam IP adresi hiçbir rolde görünmüyor çünkü hiçbir yerde saklanmıyor; yazılan şey adresin /24 (IPv6’da /48) bloğu.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent>
        {!permissions.seeAudit ? (
          <p className="text-sm text-ink-faint">Oturum listesi Sahip, Güvenlik Yöneticisi ve Denetçi rollerine açıktır.</p>
        ) : error ? (
          <Notice tone="warning">
            Oturum listesi gelmedi: {error}
            <br />
            <span className="text-xs">Bu, üyenin açık oturumu olmadığı anlamına gelmez — liste sorulamadı.</span>
          </Notice>
        ) : sessions === null ? (
          <p className="text-sm text-ink-faint">Yükleniyor…</p>
        ) : sessions.length === 0 ? (
          <EmptyState title="Açık oturum yok" description="Bu hesapta geçerli bir yenileme jetonu bulunmuyor; üye şu an hiçbir cihazda giriş yapmış değil." />
        ) : (
          <ul className="grid gap-2">
            {sessions.map((session) => {
              const expiry = session.expiresAt ? Date.parse(session.expiresAt) : NaN;
              const expired = Number.isFinite(expiry) && expiry < now;
              return (
                <li key={session.id} className="rounded-lg border border-hairline bg-surface-raised p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-sm text-ink">{deviceLabel(session.userAgent)}</span>
                    {/* Ucuncu bir hal var: ailenin hic jeton satiri yoksa
                        bitis tarihi de yok. "Etkin" demek uydurma olurdu. */}
                    {!Number.isFinite(expiry)
                      ? <Badge tone="neutral">Süresi bilinmiyor</Badge>
                      : expired
                        ? <Badge tone="neutral">Süresi dolmuş</Badge>
                        : <Badge tone="success">Etkin</Badge>}
                  </div>
                  <p className="mt-1 text-xs text-ink-faint">
                    {session.ipPrefix ? `${session.ipPrefix} · ` : 'Ağ bloğu kaydedilmemiş · '}
                    {session.lastSeenAt ? `son görülme ${formatDateTime(session.lastSeenAt)}` : 'son görülme kaydı yok'}
                  </p>
                  <p className="mt-0.5 text-xs text-ink-faint">
                    {`Açılış ${formatDateTime(session.createdAt)}`}
                    {session.expiresAt ? ` · ${expired ? 'bitiş' : 'geçerlilik'} ${formatDateTime(session.expiresAt)}` : ' · bitiş tarihi okunamadı'}
                  </p>
                </li>
              );
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

function SessionsTab({
  member, permissions, isSelf, reloadToken, onAsk,
}: {
  member: IdentityMember;
  permissions: MemberPermissions;
  isSelf: boolean;
  reloadToken: number;
  onAsk: () => void;
}) {
  const [rows, setRows] = useState<AuditRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [failures, setFailures] = useState<string[]>([]);

  useEffect(() => {
    if (!permissions.seeAudit) return;
    let active = true;
    (async () => {
      try {
        const response = await fetch(`/api/audit?actorId=${member.id}&limit=50`, { headers: { 'content-type': 'application/json' } });
        const body = await response.json().catch(() => null);
        if (!active) return;
        if (!response.ok) { setError(body?.error?.message ?? 'Denetim kaydı alınamadı.'); return; }
        setRows(body.data as AuditRow[]);
        setFailures((body.meta?.failures as string[] | undefined) ?? []);
      } catch {
        if (active) setError('Denetim kaydına ulaşılamadı.');
      }
    })();
    return () => { active = false; };
  }, [member.id, permissions.seeAudit]);

  return (
    <div className="grid gap-4">
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Oturumu sonlandır</CardTitle>
            <CardDescription>
              Hesabın tüm cihazlardaki oturumu kapanır ve üye yeniden giriş yapmak zorunda kalır. Parola değiştirilmez ve hiçbir rolde gösterilmez.
            </CardDescription>
          </div>
          <LogOut size={16} className="shrink-0 text-ink-faint" />
        </CardHeader>
        <CardContent>
          {!permissions.revokeSessions ? (
            <p className="text-sm text-ink-faint">Bu işlem Sahip ve Güvenlik Yöneticisi rollerine açıktır.</p>
          ) : isSelf ? (
            <p className="text-sm text-ink-faint">Kendi oturumlarını buradan kapatamazsın; kenar çubuğundaki “Oturumu kapat” bunun için var.</p>
          ) : (
            <Button variant="danger" onClick={onAsk}>Tüm oturumları kapat</Button>
          )}
        </CardContent>
      </Card>

      <SessionList member={member} permissions={permissions} reloadToken={reloadToken} />

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Bu hesabın panel işlemleri</CardTitle>
            {/* Deliberately narrow: the audit APIs filter by actor, not by
                target. Calling this "işlem geçmişi" would imply it also shows
                the decisions taken *about* this member, which it does not. */}
            <CardDescription>
              Bu hesabın panelde yaptığı son 50 işlem. Hakkında alınan kararlar burada değil, Sistem ve Denetim ekranında aranır — denetim uçları hedefe göre değil, işlemi yapana göre süzülüyor.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {!permissions.seeAudit ? (
            <p className="text-sm text-ink-faint">Denetim kaydı Sahip, Güvenlik Yöneticisi ve Denetçi rollerine açıktır.</p>
          ) : error ? (
            <Notice tone="warning">{error}</Notice>
          ) : rows === null ? (
            <p className="text-sm text-ink-faint">Yükleniyor…</p>
          ) : rows.length === 0 ? (
            <EmptyState title="Panel işlemi yok" description="Bu hesap panelde kayda geçen bir işlem yapmamış." />
          ) : (
            <ul className="grid gap-2">
              {rows.map((row) => (
                <li key={row.id} className="rounded-lg border border-hairline bg-surface-raised p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-sm text-ink">{actionLabel(row.action)}</span>
                    <Badge tone={row.outcome === 'succeeded' ? 'success' : row.outcome === 'denied' ? 'warning' : 'danger'}>
                      {OUTCOME_LABELS[row.outcome] ?? row.outcome}
                    </Badge>
                  </div>
                  <p className="mt-1 text-xs text-ink-faint">
                    {SERVICE_LABELS[row.service]} · {formatDateTime(row.createdAt)}
                    {row.targetType ? ` · ${row.targetType}` : ''}
                  </p>
                  {row.reason && <p className="mt-1.5 text-sm text-ink-muted">{row.reason}</p>}
                </li>
              ))}
            </ul>
          )}
          {failures.length > 0 && (
            <p className="mt-3 text-xs text-warning">
              Şu kaynaklar yanıt vermedi: {failures.join(', ')}. Liste eksik olabilir.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
