// What this file proves.
//
// The name of a notification kind is written down in four places - the CHECK on
// member_notification_preferences, the default list the two preference routes
// build their answer from, the request schema, and the filter in the bell query
// - and nothing in the type system connects them. A kind spelled one way in the
// migration and another way in the schema fails in the quietest way available:
// the member flips a switch, the request is rejected or the row is written with
// a name the bell filter never looks for, and the notification keeps arriving
// from a setting that says it is off.
//
// No database is needed to catch that. The four lists are read from the source
// and compared.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (relative: string) => readFileSync(fileURLToPath(new URL(relative, import.meta.url)), 'utf8');

const server = read('../src/server.ts');
const migration = read('../migrations/042_notification_preferences.sql');
const worker = read('../src/profile_projection_worker.ts');

/** The kinds named inside `CHECK (kind IN (...))`. */
function migrationKinds(): string[] {
  const block = /kind TEXT NOT NULL CHECK \(kind IN \(([\s\S]*?)\)\)/.exec(migration);
  assert.ok(block, 'migration 042 no longer declares a CHECK on kind');
  return [...block[1]!.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]!);
}

/** The kinds in `MUTABLE_NOTIFICATION_KINDS`, which both routes answer with. */
function defaultKinds(): string[] {
  const block = /const MUTABLE_NOTIFICATION_KINDS = \[([\s\S]*?)\] as const;/.exec(server);
  assert.ok(block, 'MUTABLE_NOTIFICATION_KINDS is gone or was reshaped');
  return [...block[1]!.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]!);
}

/** The keys the PUT body accepts. */
function schemaKinds(): string[] {
  const block = /const notificationPreferencesSchema = z\.object\(\{([\s\S]*?)\n\}\);/.exec(server);
  assert.ok(block, 'notificationPreferencesSchema is gone or was reshaped');
  return [...block[1]!.matchAll(/([a-z_]+): z\.boolean\(\)/g)].map((match) => match[1]!);
}

test('the storable kinds, the answered kinds and the accepted kinds are the same list', () => {
  const stored = migrationKinds().sort();
  assert.deepEqual(defaultKinds().sort(), stored);
  assert.deepEqual(schemaKinds().sort(), stored);
  assert.equal(stored.length, 6);
});

test('announcement and support_answer are not mutable anywhere', () => {
  // One is the answer to a question the member asked, the other is about their
  // own account. A switch for either would let somebody turn off the only
  // notification they were guaranteed to see.
  for (const kind of ['announcement', 'support_answer']) {
    assert.ok(!migrationKinds().includes(kind), `${kind} became storable as a preference`);
    assert.ok(!defaultKinds().includes(kind), `${kind} became mutable`);
  }
});

test('the bell query filters on the preference table', () => {
  // Without this the switch saves and changes nothing - the worst of the two
  // failures, because the setting screen says it worked.
  const bell = /app\.get\('\/v1\/notifications',([\s\S]*?)\n\}\);/.exec(server);
  assert.ok(bell, 'the bell route moved');
  assert.match(bell[1]!, /NOT EXISTS \(\s*SELECT 1 FROM member_notification_preferences p/);
  assert.match(bell[1]!, /p\.enabled=false/);
});

test('preferences are filtered when read, not dropped when written', () => {
  // The write path must stay ignorant of preferences: a member who mutes a kind
  // for a month and turns it back on should find what accumulated, not a gap.
  const insert = /INSERT INTO member_notifications\(user_id,kind,subject_id,last_actor_id\)/g;
  const inserts = [...server.matchAll(insert)];
  assert.ok(inserts.length >= 1, 'notifications are no longer written here');
  for (const match of inserts) {
    const around = server.slice(Math.max(0, match.index! - 600), match.index! + 600);
    assert.ok(
      !around.includes('member_notification_preferences'),
      'a notification write started consulting preferences; muting would then delete history',
    );
  }
});

test('a purged account leaves no preferences behind', () => {
  assert.match(worker, /DELETE FROM member_notification_preferences WHERE user_id=\$1/);
});
