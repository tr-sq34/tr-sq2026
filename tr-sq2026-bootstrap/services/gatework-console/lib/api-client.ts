/**
 * The one fetch wrapper the browser half of the console uses.
 *
 * Every desk had shipped its own copy - same three lines, different error
 * handling. Two of them read `body.error.message` without checking that `body`
 * parsed, so a 502 from a proxy (which answers HTML, not JSON) surfaced as
 * "Cannot read properties of null" instead of "servise ulaşılamadı".
 *
 * These routes all answer the `{ data, meta }` envelope the services use, so
 * `meta` is kept rather than discarded: the audit log reports which of its
 * three sources failed there, and dropping it would turn a partial answer into
 * a complete-looking one.
 */
export type Envelope<T> = { data: T; meta?: Record<string, unknown> };

export async function api<T>(url: string, init?: RequestInit): Promise<Envelope<T>> {
  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) },
    });
  } catch {
    // A rejected fetch is the network, not the API: saying so stops the
    // operator hunting for a permission problem that is not there.
    throw new Error('Sunucuya ulaşılamadı. Bağlantını kontrol et.');
  }

  const body = (await response.json().catch(() => null)) as (Envelope<T> & { error?: { message?: string } }) | null;
  if (!response.ok) throw new Error(body?.error?.message ?? `İşlem tamamlanamadı (HTTP ${response.status}).`);
  if (!body) throw new Error('Sunucu beklenmeyen bir yanıt verdi.');
  return body;
}

export async function apiData<T>(url: string, init?: RequestInit): Promise<T> {
  return (await api<T>(url, init)).data;
}

export const errorText = (error: unknown, fallback: string) => (error instanceof Error ? error.message : fallback);

export const formatDateTime = (value: string) =>
  new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

export const formatDate = (value: string) => new Date(value).toLocaleDateString('tr-TR', { dateStyle: 'medium' });
