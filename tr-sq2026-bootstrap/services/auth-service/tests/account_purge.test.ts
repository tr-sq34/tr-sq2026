// Bu dosyanin ispat ettigi sey.
//
// "Hesabimi sil" diyen uyeye otuz gun soz veriliyor. Sozun ikinci yarisi -
// surenin sonunda kimligin gercekten silinmesi - gozle gorulur bir sey degil:
// dogru calistiginda ekranda hicbir sey olmuyor, yanlis calistiginda da oyle.
// Bu yuzden burada test ediliyor.
//
// Veritabani gerekmiyor. Sorularin hepsi "hangi ifadeler, hangi sirayla, hangi
// degerlerle calisti" sorusu; cevabini sahte bir istemci veriyor.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import type pg from 'pg';

import { PURGED_DISPLAY_NAME, purgeDueAccounts, purgedEmail } from '../src/account_purge.ts';

type DueRow = { id: string; display_name: string; requestedDaysAgo: number };

interface Recorded {
  text: string;
  values?: unknown[];
}

/// Silme akisini disaridan izleyen sahte havuz. Sadece iki soruya cevap
/// veriyor: sirada kim var, ve kim ne yazdi.
class FakePool {
  readonly queries: Recorded[] = [];
  released = 0;
  constructor(
    private readonly due: DueRow[],
    private readonly failure?: { userId: string; statement: RegExp },
  ) {}

  async connect(): Promise<pg.PoolClient> {
    const pool = this;
    const client = {
      async query(text: string, values?: unknown[]) {
        pool.queries.push({ text, values });
        if (pool.failure && pool.failure.statement.test(text) && values?.[0] === pool.failure.userId) {
          throw new Error('database said no');
        }
        if (/FROM users/.test(text)) {
          const graceDays = Number(values?.[0]);
          const skip = (values?.[1] as string[]) ?? [];
          // Gercek sorgunun WHERE'i burada elle kuruluyor: amac SQL'i degil,
          // fonksiyonun dogru gun sayisini ve dogru atlama listesini
          // gecirdigini olcmek.
          const next = pool.due.find(
            (row) => row.requestedDaysAgo > graceDays && !skip.includes(row.id),
          );
          return { rows: next ? [{ id: next.id, display_name: next.display_name }] : [], rowCount: next ? 1 : 0 };
        }
        return { rows: [], rowCount: 0 };
      },
      release() {
        pool.released += 1;
      },
    };
    return client as unknown as pg.PoolClient;
  }

  ran(pattern: RegExp) {
    return this.queries.filter((query) => pattern.test(query.text));
  }
}

function deps(pool: FakePool) {
  const statuses: Array<{ userId: string; status: string }> = [];
  const messaging: Array<{ id: string; displayName: string; active: boolean }> = [];
  const hashed: string[] = [];
  return {
    statuses,
    messaging,
    hashed,
    input: {
      db: pool,
      async hashPassword(password: string) {
        hashed.push(password);
        return `argon2id-of-${password}`;
      },
      async queueAccountStatus(_client: pg.PoolClient, userId: string, status: string) {
        statuses.push({ userId, status });
      },
      async queueMessagingUserUpsert(
        _client: pg.PoolClient,
        user: { id: string; displayName: string; active: boolean },
      ) {
        messaging.push(user);
      },
    },
  };
}

test('suresi dolmayan hesaba dokunulmuyor', async () => {
  const pool = new FakePool([{ id: 'u-1', display_name: 'Ayse', requestedDaysAgo: 29 }]);
  const harness = deps(pool);

  const report = await purgeDueAccounts(harness.input as never);

  assert.deepEqual(report, { purged: [], failed: [] });
  // Vazgecme hakki suresince tek bir alan bile degismiyor.
  assert.equal(pool.ran(/UPDATE users/).length, 0);
  assert.equal(pool.ran(/DELETE FROM/).length, 0);
  assert.equal(pool.ran(/COMMIT/).length, 0);
  assert.equal(pool.released, 1, 'baglanti geri verilmedi');
});

test('sure dolunca kimlik siliniyor ve geriye ad kalmiyor', async () => {
  const pool = new FakePool([{ id: 'u-1', display_name: 'Ayse Yilmaz', requestedDaysAgo: 31 }]);
  const harness = deps(pool);

  const report = await purgeDueAccounts(harness.input as never);

  assert.deepEqual(report.purged, ['u-1']);
  const update = pool.ran(/UPDATE users SET email=/)[0];
  assert.ok(update, 'kimlik satiri hic yazilmadi');
  assert.equal(update.values?.[1], purgedEmail('u-1'));
  assert.equal(update.values?.[2], PURGED_DISPLAY_NAME);
  assert.match(String(update.text), /purged_at=now\(\)/);
  // E-posta hicbir zaman cozulmeyen bir alana gidiyor ve eski adres serbest
  // kaliyor: uye isterse ayni e-posta ile bastan kayit olabilmeli.
  assert.match(String(update.values?.[1]), /@hesap\.invalid$/);
});

test('kimlige bagli ne varsa ayni islemde gidiyor', async () => {
  const pool = new FakePool([{ id: 'u-1', display_name: 'Ayse', requestedDaysAgo: 40 }]);
  const harness = deps(pool);

  await purgeDueAccounts(harness.input as never);

  for (const table of [
    'refresh_token_families',
    'account_action_tokens',
    'email_verification_codes',
    'password_reset_codes',
    'webauthn_credentials',
    'webauthn_challenges',
    'user_onboarding',
  ]) {
    assert.equal(pool.ran(new RegExp(`DELETE FROM ${table} `)).length, 1, `${table} temizlenmedi`);
  }
  // Yetki geri aliniyor ama satir duruyor: kimin ne zaman yetkisi vardi sorusu
  // denetim kaydinin isi.
  assert.equal(pool.ran(/UPDATE admin_roles SET revoked_at/).length, 1);
  assert.equal(pool.ran(/COMMIT/).length, 1);
  // Tek ROLLBACK var ve COMMIT'ten sonra geliyor: sirada kimsenin kalmadigini
  // goren son turun hicbir sey yazmamis islemini kapatiyor.
  const commitAt = pool.queries.findIndex((query) => /COMMIT/.test(query.text));
  const rollbackAt = pool.queries.findIndex((query) => /ROLLBACK/.test(query.text));
  assert.equal(pool.ran(/ROLLBACK/).length, 1);
  assert.ok(rollbackAt > commitAt, 'silme islemi geri alindi');
});

test('silinen sifrenin yerine tahmin edilemeyen bir ozet yaziliyor', async () => {
  const pool = new FakePool([
    { id: 'u-1', display_name: 'Ayse', requestedDaysAgo: 31 },
    { id: 'u-2', display_name: 'Mehmet', requestedDaysAgo: 31 },
  ]);
  const harness = deps(pool);

  await purgeDueAccounts(harness.input as never);

  assert.equal(harness.hashed.length, 2);
  // Sabit bir deger yazilsaydi bir hesabin sifresini bilen herkesin sifresi
  // olurdu. Iki silme iki ayri sir uretiyor ve ikisi de hicbir yerde durmuyor.
  assert.notEqual(harness.hashed[0], harness.hashed[1]);
  assert.ok(harness.hashed[0]!.length >= 32);
});

test('Community ve Messaging ayni islemde haberdar ediliyor', async () => {
  const pool = new FakePool([{ id: 'u-1', display_name: 'Ayse', requestedDaysAgo: 31 }]);
  const harness = deps(pool);

  await purgeDueAccounts(harness.input as never);

  assert.deepEqual(harness.statuses, [{ userId: 'u-1', status: 'purged' }]);
  assert.deepEqual(harness.messaging, [
    { id: 'u-1', displayName: PURGED_DISPLAY_NAME, active: false },
  ]);
});

test('bir hesap silinemezse digerleri yine de siliniyor', async () => {
  const pool = new FakePool(
    [
      { id: 'u-1', display_name: 'Ayse', requestedDaysAgo: 31 },
      { id: 'u-2', display_name: 'Mehmet', requestedDaysAgo: 31 },
    ],
    { userId: 'u-1', statement: /DELETE FROM user_onboarding/ },
  );
  const harness = deps(pool);

  const report = await purgeDueAccounts(harness.input as never);

  assert.deepEqual(report.failed, ['u-1']);
  assert.deepEqual(report.purged, ['u-2']);
  // Yarim silme diye bir sey yok: patlayan hesabin yazdiklari geri aliniyor,
  // satir sirada kaliyor ve bir sonraki turda yeniden deneniyor.
  assert.equal(pool.ran(/ROLLBACK/).length, 2, 'biri patlayan hesap, digeri bos gecen son tur');
  assert.equal(pool.ran(/COMMIT/).length, 1);
  assert.equal(harness.statuses.length, 1);
  assert.equal(pool.released, 3, 'her tur icin bir baglanti geri verilmeli');
});

test('bir turda islenen hesap sayisi siniri asmiyor', async () => {
  const due = Array.from({ length: 5 }, (_, index) => ({
    id: `u-${index}`,
    display_name: 'Uye',
    requestedDaysAgo: 31,
  }));
  const pool = new FakePool(due);
  const harness = deps(pool);

  const report = await purgeDueAccounts({ ...harness.input, batchSize: 2 } as never);

  assert.deepEqual(report.purged, ['u-0', 'u-1']);
  // Kalanlar kaybolmuyor, bir sonraki turu bekliyor.
  assert.equal(pool.ran(/COMMIT/).length, 2);
});
