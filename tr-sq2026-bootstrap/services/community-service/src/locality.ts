// The rule that keeps the Analitik ve Konum screen aggregate.
//
// Locality was designed in migration 008 as a chosen city/state preference,
// never a continuous exact trail. Counting those preferences per city is still
// safe only while a bucket is big enough to hide in: one member in Boise, read
// next to the console's Uyeler screen and its city filter, is a name. So a
// bucket smaller than the threshold is not shown at all - it is folded into a
// single total, which keeps the sums honest without handing back the bucket.
//
// It lives here rather than inline in the route for one reason: it is the
// privacy guarantee, and a guarantee should be provable without a database.

export const LOCALITY_MIN_BUCKET = 5;

export type LocalityBucket = { members: number; posts: number; listings: number };
export type LocalityTotals = LocalityBucket & { buckets: number };

export const emptyLocalityBucket = (): LocalityBucket => ({ members: 0, posts: 0, listings: 0 });

/// Splits buckets into the ones that may be listed and one sum of the rest.
///
/// The test is the member count, not the row count: a state with four residents
/// and sixty listings is still four people, and the listings would point at
/// them. Sorted by members, then posts, so the order does not depend on the map
/// iteration order the caller happened to build.
export function suppressSmallBuckets<T extends LocalityBucket>(
  rows: T[],
  threshold = LOCALITY_MIN_BUCKET,
): { shown: T[]; suppressed: LocalityTotals } {
  const shown: T[] = [];
  const suppressed: LocalityTotals = { buckets: 0, members: 0, posts: 0, listings: 0 };
  for (const row of rows) {
    if (row.members >= threshold) { shown.push(row); continue; }
    suppressed.buckets += 1;
    suppressed.members += row.members;
    suppressed.posts += row.posts;
    suppressed.listings += row.listings;
  }
  shown.sort((a, b) => b.members - a.members || b.posts - a.posts);
  return { shown, suppressed };
}
