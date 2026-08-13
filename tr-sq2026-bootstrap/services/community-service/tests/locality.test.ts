// What this file proves.
//
// The Analitik ve Konum screen promises two things: that a small place is never
// listed on its own, and that hiding it does not quietly shrink the totals. Both
// are decided here rather than in SQL, so both can be proved without a database.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { LOCALITY_MIN_BUCKET, suppressSmallBuckets } from '../src/locality.ts';

const bucket = (name: string, members: number, posts = 0, listings = 0) => ({ name, members, posts, listings });

test('a place with fewer members than the threshold is never listed on its own', () => {
  const { shown } = suppressSmallBuckets([bucket('Boise', 1), bucket('Paterson', 40)]);
  assert.deepEqual(shown.map((row) => row.name), ['Paterson']);
});

test('exactly at the threshold is shown - the rule is fewer than, not fewer than or equal', () => {
  const { shown, suppressed } = suppressSmallBuckets([bucket('Edison', LOCALITY_MIN_BUCKET)]);
  assert.deepEqual(shown.map((row) => row.name), ['Edison']);
  assert.equal(suppressed.buckets, 0);
});

test('what is hidden is still counted, so the totals stay true', () => {
  const { suppressed } = suppressSmallBuckets([
    bucket('Boise', 1, 3, 2),
    bucket('Fargo', 2, 5, 0),
    bucket('Paterson', 40, 900, 30),
  ]);
  assert.deepEqual(suppressed, { buckets: 2, members: 3, posts: 8, listings: 2 });
});

// The threshold is about members, not activity: a state with four residents is
// four people no matter how many listings they wrote, and the listings point
// straight back at them.
test('a small place with a lot of activity is still suppressed', () => {
  const { shown, suppressed } = suppressSmallBuckets([bucket('Cheyenne', 2, 400, 90)]);
  assert.equal(shown.length, 0);
  assert.equal(suppressed.listings, 90);
});

test('the shown list is ordered by members, not by the order it was built in', () => {
  const { shown } = suppressSmallBuckets([bucket('Edison', 6), bucket('Paterson', 40), bucket('Clifton', 12)]);
  assert.deepEqual(shown.map((row) => row.name), ['Paterson', 'Clifton', 'Edison']);
});

test('nothing to suppress leaves an all-zero total rather than nothing at all', () => {
  const { shown, suppressed } = suppressSmallBuckets([]);
  assert.deepEqual(shown, []);
  assert.deepEqual(suppressed, { buckets: 0, members: 0, posts: 0, listings: 0 });
});
