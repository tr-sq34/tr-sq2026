// What this file proves.
//
// The badge catalogue is data (migration 016) and the rules that grant badges
// are code (server.ts, journey.ts, the projection worker). Nothing connects
// them: a badge can sit in the catalogue for a year with no rule behind it, and
// the only symptom is a member reading a criterion in the app that nobody can
// ever satisfy. That is exactly what had happened - twelve of about fifty
// badges are reachable.
//
// AUTOMATED_BADGE_CODES is the list the console shows the operator, per badge,
// as "kurali var" or "kurali yok". If that list drifts from the actual call
// sites, the panel lies in the most confident way possible: it tells an
// operator a broken badge is fine, or sends them chasing a rule that works.
//
// So the list is compared against the call sites in both directions, and
// against the catalogue. No database needed.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (relative: string) => readFileSync(fileURLToPath(new URL(relative, import.meta.url)), 'utf8');

const server = read('../src/server.ts');
const journey = read('../src/journey.ts');
const worker = read('../src/profile_projection_worker.ts');
const migration = read('../migrations/016_member_journey.sql');
const grants = read('../migrations/043_manual_badge_grants.sql');

const sources = [server, journey, worker].join('\n');

/** The list the console is told to trust. */
function declaredCodes(): string[] {
  const block = /export const AUTOMATED_BADGE_CODES: readonly string\[\] = \[([\s\S]*?)\];/.exec(journey);
  assert.ok(block, 'AUTOMATED_BADGE_CODES is gone or was reshaped');
  return [...block[1]!.matchAll(/'([a-z0-9_]+)'/g)].map((match) => match[1]!);
}

/**
 * Every badge code named at a grant call site.
 *
 * A call that passes a variable rather than a literal - the panel's own grant
 * route, and advanceProgress inside touchStreak - is deliberately not counted:
 * the codes it can reach are decided elsewhere, and for touchStreak that
 * "elsewhere" is the literal list read below.
 */
function grantedCodes(): string[] {
  const codes = new Set<string>();
  for (const call of sources.matchAll(/(?:awardBadge|advanceProgress)\([^)']*?,\s*'([a-z0-9_]+)'/g)) {
    codes.add(call[1]!);
  }
  for (const loop of sources.matchAll(/for \(const code of \[([^\]]*)\] as const\)/g)) {
    for (const inner of loop[1]!.matchAll(/'([a-z0-9_]+)'/g)) codes.add(inner[1]!);
  }
  return [...codes];
}

/** The catalogue as seeded. */
function catalogueCodes(): string[] {
  return [...migration.matchAll(/\n {2}\('([a-z0-9_]+)',\s+'/g)].map((match) => match[1]!);
}

test('every badge the panel calls automatic really has a rule behind it', () => {
  const declared = declaredCodes().sort();
  const granted = grantedCodes().sort();
  assert.deepEqual(declared, granted);
  assert.ok(declared.length >= 12, 'the automated list shrank unexpectedly');
});

test('every automated badge exists in the catalogue', () => {
  const catalogue = new Set(catalogueCodes());
  assert.ok(catalogue.size > 40, 'the catalogue seed could not be read');
  for (const code of declaredCodes()) {
    assert.ok(catalogue.has(code), `${code} is granted by code but is not in the catalogue`);
  }
});

test('a manual-only badge never claims to be automatic', () => {
  // solidarity_medal is the one the migration marks manual_only. If a rule ever
  // starts granting it, the human decision it stands for has quietly become a
  // side effect of something else.
  const manual = [...migration.matchAll(/\('([a-z0-9_]+)',[^\n]*?,\s*(?:true|false),\s*true,\s*\d+\)/g)].map((match) => match[1]!);
  assert.ok(manual.length >= 1, 'no manual_only badge found in the seed');
  for (const code of manual) {
    assert.ok(!declaredCodes().includes(code), `${code} is manual_only but is listed as automated`);
  }
});

test('the panel cannot hand out a badge that has a rule', () => {
  // Granting an automated badge by hand would leave the counter running, so the
  // member would watch a progress bar fill toward something they already hold.
  const route = /app\.post\('\/v1\/internal\/gatework\/journey\/badges\/:code\/grant'([\s\S]*?)\n\}\);/.exec(server);
  assert.ok(route, 'the grant route moved');
  assert.match(route[1]!, /AUTOMATED_BADGE_CODES\.includes\(code\)/);
  assert.match(route[1]!, /BADGE_AUTOMATED/);
  // And a grant is always attributed.
  assert.match(route[1]!, /grantedBy: actor\.actorId/);
  assert.match(route[1]!, /journey\.badge\.grant/);
});

test('an earned badge cannot be revoked from the panel', () => {
  const route = /app\.delete\('\/v1\/internal\/gatework\/journey\/badges\/:code\/holders\/:userId'([\s\S]*?)\n\}\);/.exec(server);
  assert.ok(route, 'the revoke route moved');
  assert.match(route[1]!, /granted_by === null\) throw Error\('BADGE_EARNED'\)/);
  assert.match(route[1]!, /journey\.badge\.revoke/);
});

test('a hand-granted badge records who gave it and why', () => {
  assert.match(grants, /ADD COLUMN IF NOT EXISTS granted_by UUID/);
  assert.match(grants, /ADD COLUMN IF NOT EXISTS granted_reason TEXT/);
  // The bell needs a UUID subject and a badge code is text.
  assert.match(grants, /ADD COLUMN IF NOT EXISTS id UUID NOT NULL DEFAULT gen_random_uuid\(\)/);
  assert.match(grants, /'badge_earned'/);
});

test('a purged account leaves no badges behind', () => {
  // The panel now lists holders by name; a purged member would otherwise sit in
  // that list as a bare identifier, next to a reason sentence written about
  // them.
  assert.match(worker, /DELETE FROM member_badges WHERE user_id=\$1/);
  assert.match(worker, /DELETE FROM member_badge_progress WHERE user_id=\$1/);
});
