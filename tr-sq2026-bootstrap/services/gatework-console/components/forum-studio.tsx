'use client';
import { useCallback, useEffect, useState } from 'react';
import { FORUM_STATE_LABELS, type ForumCategory, type ForumTopicRow } from '@/lib/forum-labels';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data as T;
}

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

export function ForumStudio({ initialCategories, canEdit, canModerate }: { initialCategories: ForumCategory[]; canEdit: boolean; canModerate: boolean }) {
  const [categories, setCategories] = useState(initialCategories);
  const [topics, setTopics] = useState<ForumTopicRow[]>([]);
  const [categoryFilter, setCategoryFilter] = useState('');
  const [stateFilter, setStateFilter] = useState('active');
  const [query, setQuery] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const loadTopics = useCallback(async (category: string, state: string, search: string) => {
    const params = new URLSearchParams({ state });
    if (category) params.set('categoryId', category);
    if (search.trim().length >= 2) params.set('query', search.trim());
    try {
      setTopics(await call<ForumTopicRow[]>(`/api/forum/topics?${params}`));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Konular alınamadı.');
    }
  }, []);

  useEffect(() => { void loadTopics(categoryFilter, stateFilter, ''); }, [loadTopics, categoryFilter, stateFilter]);

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

  const refreshCategories = async () => setCategories(await call<ForumCategory[]>('/api/forum/categories'));

  async function createCategory(form: FormData) {
    await run(async () => {
      await call('/api/forum/categories', {
        method: 'POST',
        body: JSON.stringify({
          slug: form.get('slug'),
          title: form.get('title'),
          emoji: form.get('emoji') || '💬',
          description: form.get('description') ?? '',
          ordinal: Number(form.get('ordinal') ?? 0),
          reason: form.get('reason'),
        }),
      });
      await refreshCategories();
    }, 'Kategori açıldı.');
  }

  function patchCategory(category: ForumCategory, patch: Record<string, unknown>, prompt_: string) {
    const reason = window.prompt(`${prompt_}\n\nGerekçe (denetim kaydına yazılır, en az 5 karakter):`)?.trim();
    if (!reason || reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı; işlem yapılmadı.'); return; }
    void run(async () => {
      await call(`/api/forum/categories/${category.id}`, { method: 'PATCH', body: JSON.stringify({ ...patch, reason }) });
      await refreshCategories();
    }, 'Kategori güncellendi.');
  }

  function setTopicState(topic: ForumTopicRow, patch: { isPinned?: boolean; isLocked?: boolean }, prompt_: string) {
    const reason = window.prompt(`${prompt_}\n\nGerekçe (denetim kaydına yazılır, en az 5 karakter):`)?.trim();
    if (!reason || reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı; işlem yapılmadı.'); return; }
    void run(async () => {
      const next = await call<{ id: string; isPinned: boolean; isLocked: boolean }>(`/api/forum/topics/${topic.id}/state`, { method: 'POST', body: JSON.stringify({ ...patch, reason }) });
      setTopics((current) => current.map((row) => (row.id === next.id ? { ...row, isPinned: next.isPinned, isLocked: next.isLocked } : row)));
    }, 'Konu durumu güncellendi.');
  }

  const field = 'mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  const secondary = 'rounded-lg bg-zinc-800 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40';

  return (
    <div className="grid gap-8">
      <section>
        <h2 className="text-lg font-semibold">Kategoriler</h2>
        {/* Retiring, not deleting: a closed category still owns a year of
            answers, and those have to stay readable. */}
        <p className="mt-1 max-w-2xl text-sm text-zinc-400">Kapatılan kategori silinmez; yeni konu almaz, içindeki konular okunmaya devam eder. Kısa ad (slug) sonradan değiştirilemez, çünkü bağlantılar ve kayıtlı filtreler ona bağlıdır.</p>
        <div className="mt-4 grid gap-3">
          {categories.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Henüz kategori yok.</p>}
          {categories.map((category) => (
            <article key={category.id} className={`flex flex-wrap items-center justify-between gap-4 rounded-xl border p-4 ${category.isActive ? 'border-white/10 bg-zinc-900/40' : 'border-zinc-800 bg-zinc-950/60'}`}>
              <div className="min-w-0">
                <p className="text-sm text-zinc-100"><span className="mr-2">{category.emoji}</span>{category.title} {!category.isActive && <span className="ml-2 rounded bg-zinc-800 px-2 py-0.5 text-[11px] text-zinc-400">kapalı</span>}</p>
                <p className="truncate text-xs text-zinc-500">/{category.slug} · sıra {category.ordinal} · {category.topicCount} konu · {category.replyCount} yanıt · {category.lastActivityAt ? `son hareket ${time(category.lastActivityAt)}` : 'hareket yok'}</p>
                {category.description && <p className="mt-1 max-w-xl text-xs text-zinc-400">{category.description}</p>}
              </div>
              {canEdit && (
                <div className="flex gap-2">
                  <button type="button" disabled={busy} className={secondary} onClick={() => {
                    const title = window.prompt('Yeni başlık:', category.title)?.trim();
                    if (!title || title.length < 2) { setMessage('Başlık en az 2 karakter olmalı; işlem yapılmadı.'); return; }
                    patchCategory(category, { title }, `"${category.title}" kategorisi "${title}" olarak yeniden adlandırılacak.`);
                  }}>Yeniden adlandır</button>
                  <button type="button" disabled={busy} className={secondary} onClick={() => patchCategory(category, { isActive: !category.isActive }, category.isActive ? `"${category.title}" kategorisi kapatılacak; yeni konu alınmaz.` : `"${category.title}" kategorisi yeniden açılacak.`)}>{category.isActive ? 'Kapat' : 'Aç'}</button>
                </div>
              )}
            </article>
          ))}
        </div>

        {canEdit && (
          <form action={createCategory} className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
            <h3 className="font-semibold">Yeni kategori</h3>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <label className="block text-sm">Başlık
                <input name="title" required minLength={2} maxLength={80} className={field} placeholder="Vize &amp; Göçmenlik" />
              </label>
              <label className="block text-sm">Kısa ad <span className="text-zinc-600">(küçük harf, tire)</span>
                <input name="slug" required pattern="[a-z0-9-]{2,48}" className={field} placeholder="vize-gocmenlik" />
              </label>
              <label className="block text-sm">Simge
                <input name="emoji" maxLength={8} className={field} placeholder="🎓" />
              </label>
              <label className="block text-sm">Sıra
                <input name="ordinal" type="number" min={0} max={999} defaultValue={0} className={field} />
              </label>
            </div>
            <label className="mt-4 block text-sm">Açıklama
              <input name="description" maxLength={240} className={field} placeholder="Vize türleri, yeşil kart, vatandaşlık ve randevular" />
            </label>
            <label className="mt-4 block text-sm">Gerekçe <span className="text-zinc-600">(denetim kaydına yazılır)</span>
              <textarea name="reason" required minLength={5} maxLength={500} rows={2} className={field} />
            </label>
            <button disabled={busy} className="mt-4 rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">Kategoriyi aç</button>
          </form>
        )}
      </section>

      <section>
        <h2 className="text-lg font-semibold">Konular</h2>
        <p className="mt-1 max-w-2xl text-sm text-zinc-400">Sabitlenen konu listenin başında durur; kilitlenen konu okunur ama yeni yanıt almaz. İçerik kaldırma bu ekranda değil, Moderasyon Merkezi&apos;ndeki şikâyet kuyruğunda yapılır.</p>
        <form
          className="mt-4 flex flex-wrap gap-2"
          onSubmit={(event) => { event.preventDefault(); void loadTopics(categoryFilter, stateFilter, query); }}
        >
          <select value={categoryFilter} onChange={(event) => setCategoryFilter(event.target.value)} className="rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400">
            <option value="">Tüm kategoriler</option>
            {categories.map((category) => <option key={category.id} value={category.id}>{category.title}</option>)}
          </select>
          <select value={stateFilter} onChange={(event) => setStateFilter(event.target.value)} className="rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400">
            <option value="active">Yayında</option>
            <option value="hidden">Gizlenmiş</option>
            <option value="removed">Kaldırılmış</option>
            <option value="all">Hepsi</option>
          </select>
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Başlıkta ara (en az 2 harf)" className="min-w-[220px] flex-1 rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400" />
          <button className="rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950">Ara</button>
        </form>

        <ul className="mt-4 grid gap-2">
          {topics.length === 0 && <li className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Bu filtrede konu yok.</li>}
          {topics.map((topic) => (
            <li key={topic.id} className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-white/10 bg-zinc-900/40 p-4">
              <div className="min-w-0">
                <p className="truncate text-sm text-zinc-100">
                  {topic.isPinned && <span className="mr-2 rounded bg-emerald-400/20 px-1.5 py-0.5 text-[11px] text-emerald-300">sabit</span>}
                  {topic.isLocked && <span className="mr-2 rounded bg-amber-500/20 px-1.5 py-0.5 text-[11px] text-amber-200">kilitli</span>}
                  {topic.moderationState !== 'active' && <span className="mr-2 rounded bg-rose-500/20 px-1.5 py-0.5 text-[11px] text-rose-300">{FORUM_STATE_LABELS[topic.moderationState] ?? topic.moderationState}</span>}
                  {topic.title}
                </p>
                <p className="truncate text-xs text-zinc-500">{topic.categoryTitle} · {topic.authorName ?? topic.authorId.slice(0, 8)} · {topic.replyCount} yanıt · {topic.viewCount} görüntülenme · son hareket {time(topic.lastActivityAt)}</p>
              </div>
              {canModerate && (
                <div className="flex gap-2">
                  <button type="button" disabled={busy} className={secondary} onClick={() => setTopicState(topic, { isPinned: !topic.isPinned }, topic.isPinned ? `"${topic.title}" sabitlemesi kaldırılacak.` : `"${topic.title}" listenin başına sabitlenecek.`)}>{topic.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'}</button>
                  <button type="button" disabled={busy} className={secondary} onClick={() => setTopicState(topic, { isLocked: !topic.isLocked }, topic.isLocked ? `"${topic.title}" yeniden yanıt alacak.` : `"${topic.title}" yeni yanıt almayacak.`)}>{topic.isLocked ? 'Kilidi aç' : 'Kilitle'}</button>
                </div>
              )}
            </li>
          ))}
        </ul>
      </section>

      {message && <p className="rounded-lg border border-white/10 bg-zinc-900 p-3 text-sm text-zinc-300">{message}</p>}
    </div>
  );
}
