import { randomBytes } from 'node:crypto';

import type pg from 'pg';

/**
 * Bekleme suresi dolan hesaplarin kalici temizligi.
 *
 * `/v1/auth/account/delete` uyeye otuz gun soz veriyor: o gune kadar giris
 * yapmak silme talebini geri aliyor, o gunden sonra kimlik siliniyor. Sozun
 * ikinci yarisini tutan kod burasi.
 *
 * Neden satir silinmiyor: migrations/014_account_purge.sql. Kisaca, users(id)
 * satirina bagli olan seylerin arasinda "bu hesap silindi" olayini tasiyacak
 * outbox kaydi da var; satiri silen islem haberi de silerdi.
 */

export const ACCOUNT_DELETION_GRACE_DAYS = 30;

/// Silinmis bir hesabin adi. Community ve Messaging projeksiyonlarinda da bu
/// yaziyor: eski isim uc yerde birden duruyorsa yalnizca birini silmek hicbir
/// sey silmemek demek.
export const PURGED_DISPLAY_NAME = 'Silinmiş üye';

/// `.invalid` RFC 2606'nin ayirdigi ad: hicbir zaman cozulmez, dolayisiyla bu
/// adrese kazara bir posta gonderilemez. Kullanici kimligi adresin icinde
/// duruyor cunku e-posta sutunu benzersiz; sabit bir adres ikinci silmede
/// catisirdi. Eski adres artik hicbir yerde yok, o yuzden uye isterse ayni
/// e-posta ile bastan kayit olabiliyor.
export const purgedEmail = (userId: string) => `silinmis-${userId}@hesap.invalid`;

export type AccountStatus = 'active' | 'frozen' | 'deletion_pending' | 'purged';

/**
 * Uc zaman damgasindan tek bir durum.
 *
 * Sira onemli: temizlenmis bir satirda deletion_requested_at hala dolu duruyor
 * - talebin ne zaman yapildigi kaydin bir parcasi. Once ona bakan bir kod,
 * silinmis hesabi hala "silinmeyi bekliyor" diye gosterirdi.
 */
export const accountStatusOf = (row: {
  deactivated_at: Date | null;
  deletion_requested_at: Date | null;
  purged_at: Date | null;
}): AccountStatus =>
  row.purged_at ? 'purged'
    : row.deletion_requested_at ? 'deletion_pending'
      : row.deactivated_at ? 'frozen'
        : 'active';

/// Kimlige bagli, uyeye ait ne varsa. Sirasi onemli degil - hepsi tek islemde.
/// users satirinin kendisi asagida ayrica temizleniyor.
const SCRUB_STATEMENTS = [
  'DELETE FROM refresh_token_families WHERE user_id=$1',
  'DELETE FROM account_action_tokens WHERE user_id=$1',
  'DELETE FROM email_verification_codes WHERE user_id=$1',
  'DELETE FROM password_reset_codes WHERE user_id=$1',
  'DELETE FROM webauthn_credentials WHERE user_id=$1',
  'DELETE FROM webauthn_challenges WHERE user_id=$1',
  'DELETE FROM user_onboarding WHERE user_id=$1',
  // Yetki satiri silinmiyor, geri aliniyor: kimin ne zaman yetkisi vardi
  // sorusunun cevabi denetim kaydinin bir parcasi.
  'UPDATE admin_roles SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL',
] as const;

export interface PurgeDeps {
  db: { connect(): Promise<pg.PoolClient> };
  hashPassword(password: string): Promise<string>;
  queueAccountStatus(client: pg.PoolClient, userId: string, status: AccountStatus): Promise<void>;
  queueMessagingUserUpsert(
    client: pg.PoolClient,
    user: { id: string; displayName: string; active: boolean },
  ): Promise<void>;
  log?: { info(object: unknown, message: string): void; warn(object: unknown, message: string): void };
  graceDays?: number;
  /// Bir turda en fazla kac hesap. Silme nadir bir olay; yuz binlik bir kuyruk
  /// olusmasi beklenmiyor, ama olusursa da veritabanini tek seferde mesgul
  /// etmesin diye turlara boluniyor.
  batchSize?: number;
}

export interface PurgeReport {
  purged: string[];
  failed: string[];
}

/**
 * Suresi dolan hesaplari sirayla temizler.
 *
 * Her hesap kendi isleminde: aralarindan biri patlarsa digerleri yine de
 * silinmis oluyor. Basarisiz olan bu turda bir daha denenmiyor (yoksa ayni
 * satir uzerinde sonsuz donerdi), ama satir hala sirada oldugu icin bir sonraki
 * turda tekrar deneniyor.
 */
export async function purgeDueAccounts(deps: PurgeDeps): Promise<PurgeReport> {
  const graceDays = deps.graceDays ?? ACCOUNT_DELETION_GRACE_DAYS;
  const batchSize = deps.batchSize ?? 25;
  const report: PurgeReport = { purged: [], failed: [] };

  for (let attempt = 0; attempt < batchSize; attempt += 1) {
    const skip = [...report.purged, ...report.failed];
    let account: { id: string; display_name: string } | undefined;
    const client = await deps.db.connect();
    try {
      await client.query('BEGIN');
      // FOR UPDATE SKIP LOCKED: birden fazla kopya calisiyor. Kilitli satiri
      // beklemek yerine atlamak, iki kopyanin ayni hesabi iki kez silmeye
      // calismasini ve birinin digerini beklemesini birlikte cozuyor.
      const due = await client.query<{ id: string; display_name: string }>(
        `SELECT id,display_name FROM users
          WHERE deletion_requested_at IS NOT NULL
            AND purged_at IS NULL
            AND deletion_requested_at < now() - make_interval(days => $1::int)
            AND NOT (id = ANY($2::uuid[]))
          ORDER BY deletion_requested_at
          LIMIT 1
          FOR UPDATE SKIP LOCKED`,
        [graceDays, skip],
      );
      account = due.rows[0];
      if (!account) {
        await client.query('ROLLBACK');
        return report;
      }
      await purgeAccount(client, account.id, deps);
      await client.query('COMMIT');
      report.purged.push(account.id);
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (!account) {
        deps.log?.warn({ err: error }, 'Account purge sweep failed');
        return report;
      }
      report.failed.push(account.id);
      deps.log?.warn({ err: error, userId: account.id }, 'Account purge failed; will retry next sweep');
    } finally {
      client.release();
    }
  }

  return report;
}

async function purgeAccount(client: pg.PoolClient, userId: string, deps: PurgeDeps) {
  for (const statement of SCRUB_STATEMENTS) {
    await client.query(statement, [userId]);
  }
  // Sifre alani bos birakilamiyor (NOT NULL) ve duz bir metin de yazilamiyor:
  // giris yolu argon2.verify cagiriyor, gecersiz bicimdeki bir ozet exception
  // atar ve uye "sifre hatali" yerine sunucu hatasi gorurdu. Bu yuzden hicbir
  // yerde saklanmayan, bu satirdan sonra unutulan rastgele bir sirrin ozeti
  // yaziliyor: dogrulama duzgun calisip her zaman "hayir" diyor.
  const unusablePassword = await deps.hashPassword(randomBytes(32).toString('base64url'));
  await client.query(
    'UPDATE users SET email=$2,display_name=$3,password_hash=$4,purged_at=now(),updated_at=now() WHERE id=$1',
    [userId, purgedEmail(userId), PURGED_DISPLAY_NAME, unusablePassword],
  );
  // Community profili aramada ve akista, Messaging ise sohbet listesinde eski
  // adi tutuyor. Iki olay da bu islemin icinde yazildigi icin "silindi ama
  // haber gitmedi" diye bir ara durum yok.
  await deps.queueAccountStatus(client, userId, 'purged');
  await deps.queueMessagingUserUpsert(client, { id: userId, displayName: PURGED_DISPLAY_NAME, active: false });
}
