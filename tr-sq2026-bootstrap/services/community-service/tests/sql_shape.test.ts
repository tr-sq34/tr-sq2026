// What this file proves.
//
// Every SQL string this service builds closes the parentheses it opens.
//
// It is here because of a single missing ")" in the Story access condition. The
// fragment was written once and pasted into three queries - the Story list, the
// view record and the like - so all three died with `syntax error at or near
// "ORDER"`. Nothing in the type system objects to an unbalanced string, the
// build was clean, and the app said "Story'ler su anda yuklenemedi" without
// saying why. The bug lived until someone read the database error in the logs.
//
// A database is not needed to catch that. The condition is decided by counting.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SOURCES = ['../src/server.ts', '../src/media_processor_worker.ts', '../src/profile_projection_worker.ts'];

/**
 * Template literals, with `${...}` treated as opaque.
 *
 * The placeholders are skipped rather than counted: `$${params.length}` and
 * `${storyAccessWhere('s', '$1')}` are code, not SQL, and their own brackets
 * would drown out the thing being measured.
 */
function templateLiterals(source: string): { line: number; text: string }[] {
  const found: { line: number; text: string }[] = [];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] !== '`') continue;
    let end = index + 1;
    let placeholders = 0;
    const parts: string[] = [];
    while (end < source.length) {
      if (source[end] === '\\') { end += 2; continue; }
      if (source[end] === '`' && placeholders === 0) break;
      if (source[end] === '$' && source[end + 1] === '{') placeholders += 1;
      else if (source[end] === '}' && placeholders > 0) placeholders -= 1;
      else if (placeholders === 0) parts.push(source[end]!);
      end += 1;
    }
    found.push({ line: source.slice(0, index).split('\n').length, text: parts.join('') });
    index = end;
  }
  return found;
}

const isSql = (text: string) => /\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|WHERE)\b/.test(text);

function unclosed(text: string) {
  let depth = 0;
  let closedTooMany = false;
  for (const character of text) {
    if (character === '(') depth += 1;
    else if (character === ')') { depth -= 1; if (depth < 0) closedTooMany = true; }
  }
  return { depth, closedTooMany };
}

for (const relative of SOURCES) {
  const path = fileURLToPath(new URL(relative, import.meta.url));
  const name = relative.replace('../src/', '');

  test(`${name}: every SQL string closes what it opens`, () => {
    const offenders = templateLiterals(readFileSync(path, 'utf8'))
      .filter((literal) => isSql(literal.text))
      .map((literal) => ({ ...literal, ...unclosed(literal.text) }))
      .filter((literal) => literal.depth !== 0 || literal.closedTooMany)
      .map((literal) => `${name}:${literal.line} (${literal.depth > 0 ? `${literal.depth} acik parantez` : 'fazladan kapanis'}) ${literal.text.slice(0, 120).replace(/\s+/g, ' ')}`);

    assert.deepEqual(offenders, [], `Dengelenmemis SQL:\n${offenders.join('\n')}`);
  });
}

// The fragment that caused this file. Kept as its own case so a regression
// names the Story rail rather than a line number in a large file.
test('the Story access condition is a self-contained boolean', () => {
  const source = readFileSync(fileURLToPath(new URL('../src/server.ts', import.meta.url)), 'utf8');
  const fragment = templateLiterals(source).find((literal) => literal.text.includes('story_audience_exclusions x WHERE'));
  assert.ok(fragment, 'storyAccessWhere bulunamadi - adi degistiyse bu testi de guncelle.');
  assert.deepEqual(unclosed(fragment.text), { depth: 0, closedTooMany: false });
});
