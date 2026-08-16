// What this file proves.
//
// The login screen says "Devam ederek Kullanim Kosullari ve Gizlilik
// Politikasi'ni kabul etmis olursunuz". Two things have to hold for that
// sentence to be true, and both are easy to break without noticing:
//
//   1. The member can reach the text without being signed in. The link sits
//      under a login form - if the route needs a token, the one person who
//      most needs to read it is the one who cannot.
//   2. A published version is never edited in place. If it were, "the terms I
//      accepted in March" would be a sentence with no referent.
//
// No database needed: these are properties of the source.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (relative: string) => readFileSync(fileURLToPath(new URL(relative, import.meta.url)), 'utf8');

const server = read('../src/server.ts');
const migration = read('../migrations/044_legal_documents.sql');

const route = (pattern: RegExp) => {
  const match = pattern.exec(server);
  assert.ok(match, `route not found: ${pattern}`);
  return match[1]!;
};

test('the text is readable without signing in', () => {
  const body = route(/app\.get\('\/v1\/public\/legal\/:kind'([\s\S]*?)\n\}\);/);
  // viewer() is what demands a token. Its absence here is the whole point.
  assert.ok(!body.includes('viewer('), 'the public legal route started asking for a token');
  assert.match(body, /published_at IS NOT NULL/);
  assert.match(body, /ORDER BY version DESC LIMIT 1/);
});

test('an unpublished document reads as missing, not as empty', () => {
  // A blank page would say the document is blank. It is not blank; it does not
  // exist yet, and the app has to be able to tell the member which one it is.
  const body = route(/app\.get\('\/v1\/public\/legal\/:kind'([\s\S]*?)\n\}\);/);
  assert.match(body, /LEGAL_NOT_PUBLISHED/);
  assert.match(body, /reply\.code\(404\)/);
  // And a read failure is a 500, not a 404: "could not be read" and "was never
  // written" are different answers.
  assert.match(body, /reply\.code\(500\)[\s\S]*?LEGAL_UNAVAILABLE/);
});

test('drafting and publishing are different permissions', () => {
  assert.match(server, /const LEGAL_DRAFT_ROLES: GateworkRole\[\] = \['owner', 'operations_admin', 'content_editor'\]/);
  assert.match(server, /const LEGAL_PUBLISH_ROLES: GateworkRole\[\] = \['owner', 'security_admin'\]/);
  const draft = route(/app\.put\('\/v1\/internal\/gatework\/legal\/:kind\/draft'([\s\S]*?)\n\}\);/);
  const publish = route(/app\.post\('\/v1\/internal\/gatework\/legal\/:kind\/publish'([\s\S]*?)\n\}\);/);
  assert.match(draft, /requireGateworkRole\(actor, LEGAL_DRAFT_ROLES\)/);
  assert.match(publish, /requireGateworkRole\(actor, LEGAL_PUBLISH_ROLES\)/);
});

test('a published version is never rewritten', () => {
  const draft = route(/app\.put\('\/v1\/internal\/gatework\/legal\/:kind\/draft'([\s\S]*?)\n\}\);/);
  // The upsert can only land on a row with no published_at - that is what the
  // partial index it infers is for.
  assert.match(draft, /ON CONFLICT \(kind\) WHERE published_at IS NULL/);
  assert.match(migration, /CREATE UNIQUE INDEX legal_documents_single_draft\s+ON legal_documents \(kind\) WHERE published_at IS NULL;/);
  const publish = route(/app\.post\('\/v1\/internal\/gatework\/legal\/:kind\/publish'([\s\S]*?)\n\}\);/);
  assert.match(publish, /WHERE kind=\$1 AND published_at IS NULL FOR UPDATE/);
  assert.match(publish, /LEGAL_NO_DRAFT/);
});

test('both acts are auditable', () => {
  assert.match(server, /action: 'legal\.draft\.save'/);
  assert.match(server, /action: 'legal\.publish'/);
});

test('the seeded texts are drafts, so nothing reaches a member unreviewed', () => {
  // Seeding a published privacy policy would mean the app started making legal
  // promises that no human had read.
  const insert = /INSERT INTO legal_documents \(([^)]*)\) VALUES/.exec(migration);
  assert.ok(insert, 'the seed insert moved');
  const columns = insert[1]!.split(',').map((column) => column.trim());
  assert.ok(!columns.includes('published_at'), 'the seed publishes a document');
  assert.ok(!columns.includes('published_by'), 'the seed attributes a publication to nobody');
  for (const kind of ["'privacy'", "'terms'"]) {
    assert.ok(migration.includes(`(${kind}, 1,`), `${kind} has no starting draft`);
  }
});
