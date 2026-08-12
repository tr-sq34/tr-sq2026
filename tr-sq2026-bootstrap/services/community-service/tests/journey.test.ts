// What this file does and does not prove.
//
// The badge engine's idempotency ultimately rests on Postgres: a primary key on
// member_badges and ON CONFLICT DO NOTHING. No fake can prove Postgres keeps its
// word, and there is no database in the test environment, so these tests cover
// the half that is ours - that the engine asks for the conflict clause, believes
// the answer, and never adds XP a second time when the answer is "already had
// it". The other half is covered by the migration's PRIMARY KEY.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type pg from 'pg';

import {
  advanceProgress,
  awardBadge,
  recomputeScore,
  reporterTrust,
  touchStreak,
} from '../src/journey.ts';

type Reply = { rowCount?: number; rows?: Record<string, unknown>[] };

/// A client that records every statement and answers from a script keyed on a
/// fragment of the SQL, so a test says "the insert conflicts" without having to
/// reproduce the whole statement.
class FakeClient {
  readonly calls: { sql: string; params: unknown[] }[] = [];

  constructor(private readonly script: (sql: string, params: unknown[]) => Reply | undefined = () => undefined) {}

  async query(sql: string, params: unknown[] = []): Promise<Reply> {
    this.calls.push({ sql, params });
    const reply = this.script(sql, params) ?? {};
    const rows = reply.rows ?? [];
    return { rowCount: reply.rowCount ?? rows.length, rows };
  }

  /// The engine is written against pg's client; the tests only need `query`.
  get asClient(): pg.PoolClient {
    return this as unknown as pg.PoolClient;
  }

  matching(fragment: string): { sql: string; params: unknown[] }[] {
    return this.calls.filter((call) => call.sql.includes(fragment));
  }
}

test('the same event twice grants one badge and one lot of XP', async () => {
  const first = new FakeClient((sql) =>
    sql.includes('INSERT INTO member_badges') ? { rows: [{ badge_code: 'first_post' }] } : undefined,
  );
  assert.equal(await awardBadge(first.asClient, 'u1', 'first_post'), true);
  assert.equal(first.matching('UPDATE member_scores').length, 1);

  // Replaying the same event: the insert conflicts, so nothing is recomputed
  // and the caller is told not to celebrate again.
  const replay = new FakeClient();
  assert.equal(await awardBadge(replay.asClient, 'u1', 'first_post'), false);
  assert.equal(replay.matching('UPDATE member_scores').length, 0);
  assert.equal(replay.calls.length, 1);
});

test('the grant asks Postgres to swallow the conflict', async () => {
  const client = new FakeClient();
  await awardBadge(client.asClient, 'u1', 'first_post');

  const insert = client.matching('INSERT INTO member_badges')[0]!;
  assert.match(insert.sql, /ON CONFLICT DO NOTHING/);
});

test('a medal a human is supposed to decide is not on offer to the engine', async () => {
  const engine = new FakeClient();
  await awardBadge(engine.asClient, 'u1', 'solidarity_medal');
  const [insert] = engine.matching('INSERT INTO member_badges');
  assert.match(insert!.sql, /NOT d\.manual_only/);
  assert.equal(insert!.params[2], false);

  const admin = new FakeClient();
  await awardBadge(admin.asClient, 'u1', 'solidarity_medal', { allowManual: true });
  assert.equal(admin.matching('INSERT INTO member_badges')[0]!.params[2], true);
});

test('points are re-summed, never incremented', async () => {
  const client = new FakeClient();
  await recomputeScore(client.asClient, 'u1');

  const update = client.matching('UPDATE member_scores')[0]!;
  assert.match(update.sql, /SET points=earned\.points/);
  // An increment that runs twice is unrecoverable; this is the guard against
  // someone "optimising" the sum away.
  assert.doesNotMatch(update.sql, /points\s*=\s*[a-z_.]*points\s*\+/);
});

test('a counter stops moving once its badge is held', async () => {
  const client = new FakeClient((sql) =>
    sql.includes('SELECT 1 FROM member_badges') ? { rows: [{ '?column?': 1 }] } : undefined,
  );

  assert.equal(await advanceProgress(client.asClient, 'u1', 'observer', 1), false);
  assert.equal(client.matching('member_badge_progress').length, 0);
});

test('a counter that reaches its target grants the badge', async () => {
  const client = new FakeClient((sql) => {
    if (sql.includes('SELECT 1 FROM member_badges')) return { rows: [] };
    if (sql.includes('INSERT INTO member_badge_progress')) return { rows: [{ current: 5 }] };
    if (sql.includes('INSERT INTO member_badges')) return { rows: [{ badge_code: 'observer' }] };
    return undefined;
  });

  assert.equal(await advanceProgress(client.asClient, 'u1', 'observer', 1), true);
});

test('a count that is already the total is assigned, not added', async () => {
  const client = new FakeClient((sql) =>
    sql.includes('INSERT INTO member_badge_progress') ? { rows: [{ current: 3 }] } : undefined,
  );

  await advanceProgress(client.asClient, 'u1', 'observer', 3, { absolute: true });
  const upsert = client.matching('INSERT INTO member_badge_progress')[0]!;
  // $5 is the absolute flag: true assigns $3, false adds it. A retry that
  // re-added a COUNT(*) would hand out the badge early.
  assert.match(upsert.sql, /WHEN \$5::boolean THEN \$3 ELSE member_badge_progress\.current\+\$3/);
  assert.equal(upsert.params[4], true);
  assert.equal(upsert.params[3], 5); // observer's target, read from BADGE_TARGETS
});

test('a badge with no target is a programming error, not a silent no-op', async () => {
  const client = new FakeClient();
  await assert.rejects(
    () => advanceProgress(client.asClient, 'u1', 'first_post', 1),
    /No progress target for badge first_post/,
  );
});

test('the streak feeds the streak badges its true length', async () => {
  const client = new FakeClient((sql) => {
    if (sql.includes('UPDATE member_scores') && sql.includes('streak_days')) return { rows: [{ streak_days: 14 }] };
    if (sql.includes('SELECT 1 FROM member_badges')) return { rows: [] };
    if (sql.includes('INSERT INTO member_badge_progress')) return { rows: [{ current: 14 }] };
    return undefined;
  });

  assert.equal(await touchStreak(client.asClient, 'u1'), 14);
  const progress = client.matching('INSERT INTO member_badge_progress');
  assert.deepEqual(progress.map((call) => call.params[1]), [
    'streak_master_14',
    'streak_master_30',
    'founding_architect',
  ]);
  // Called on any action, so it must be safe twenty times a day: absolute.
  assert.ok(progress.every((call) => call.params[4] === true));
});

test('a frozen account carries no weight in the moderator queue', async () => {
  const trusted = new FakeClient(() => ({ rows: [{ level: 12, frozen: false }] }));
  assert.equal(await reporterTrust(trusted.asClient, 'u1'), 'high');

  const frozen = new FakeClient(() => ({ rows: [{ level: 40, frozen: true }] }));
  assert.equal(await reporterTrust(frozen.asClient, 'u1'), 'standard');

  const newcomer = new FakeClient(() => ({ rows: [{ level: 9, frozen: false }] }));
  assert.equal(await reporterTrust(newcomer.asClient, 'u1'), 'standard');

  const unknown = new FakeClient(() => ({ rows: [] }));
  assert.equal(await reporterTrust(unknown.asClient, 'u1'), 'standard');
});
