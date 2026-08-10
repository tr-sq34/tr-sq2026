// Gurbet Yolculugu: the one place a badge is granted and a score is recomputed.
//
// Two callers need this - the HTTP server (a post, a comment, a report) and the
// identity projection worker (onboarding finished, identity verified) - and the
// rule that must hold across both is that awarding is idempotent. Both entry
// points sit behind at-least-once delivery or a retried request, so "the same
// thing happened twice" has to mean one badge and one lot of XP.
//
// Points are never incremented. They are re-summed from member_badges every
// time, because an increment that runs twice is unrecoverable while a sum that
// runs twice is simply the same number.

import type pg from 'pg';

/// Every counter-based badge and what it counts up to. The engine reads this to
/// know a target without the caller having to hardcode it at each call site.
export const BADGE_TARGETS: Record<string, number> = {
  observer: 5,
  mover_hunter: 5,
  sublet_lighthouse: 10,
  warm_tea_friend: 10,
  content_machine: 50,
  neighborhood_sentinel: 10,
  network_master: 5,
  streak_master_14: 14,
  streak_master_30: 30,
  founding_architect: 365,
  jetlag_victim: 5,
  night_owl_legend: 100,
};

/// Recomputes points, level and badge count from the badges actually held.
///
/// Runs inside the caller's transaction: a member who sees a badge appear must
/// see the XP that comes with it in the same breath.
export async function recomputeScore(client: pg.PoolClient, userId: string): Promise<void> {
  await client.query(
    `INSERT INTO member_scores(user_id) VALUES($1) ON CONFLICT DO NOTHING`,
    [userId],
  );
  await client.query(
    `WITH earned AS (
       SELECT COALESCE(sum(d.points),0)::int points, count(*)::int badges
         FROM member_badges b JOIN badge_definitions d ON d.code=b.badge_code
        WHERE b.user_id=$1
     )
     UPDATE member_scores s
        SET points=earned.points,
            badge_count=earned.badges,
            level=COALESCE((SELECT max(l.level) FROM journey_levels l WHERE l.min_points<=earned.points),1),
            updated_at=now()
       FROM earned
      WHERE s.user_id=$1`,
    [userId],
  );
}

/// Grants a badge if the member does not already hold it.
///
/// Returns true only when this call is the one that granted it, so the caller
/// can decide to celebrate exactly once. A manual-only badge (the solidarity
/// medal) is refused here rather than at the call site: the engine should not be
/// able to hand out something a human is supposed to decide.
export async function awardBadge(
  client: pg.PoolClient,
  userId: string,
  code: string,
  options: { allowManual?: boolean } = {},
): Promise<boolean> {
  const inserted = await client.query(
    `INSERT INTO member_badges(user_id,badge_code)
     SELECT $1,$2 FROM badge_definitions d
      WHERE d.code=$2 AND ($3::boolean OR NOT d.manual_only)
     ON CONFLICT DO NOTHING
     RETURNING badge_code`,
    [userId, code, options.allowManual === true],
  );
  if (!inserted.rowCount) return false;
  await recomputeScore(client, userId);
  return true;
}

/// Moves a counter forward and grants the badge when it reaches its target.
///
/// [amount] is added rather than assigned so a caller that only knows "one more
/// happened" does not have to count from zero. Callers that do know the true
/// total pass `absolute: true`, which is the honest option when the number comes
/// from a COUNT(*) - re-adding on a retry would otherwise inflate it.
export async function advanceProgress(
  client: pg.PoolClient,
  userId: string,
  code: string,
  amount: number,
  options: { absolute?: boolean } = {},
): Promise<boolean> {
  const target = BADGE_TARGETS[code];
  if (!target) throw new Error(`No progress target for badge ${code}`);
  const held = await client.query('SELECT 1 FROM member_badges WHERE user_id=$1 AND badge_code=$2', [userId, code]);
  if (held.rowCount) return false;
  const row = await client.query<{ current: number }>(
    `INSERT INTO member_badge_progress(user_id,badge_code,current,target)
     VALUES($1,$2,LEAST($3,$4),$4)
     ON CONFLICT(user_id,badge_code) DO UPDATE
       SET current=LEAST($4, CASE WHEN $5::boolean THEN $3 ELSE member_badge_progress.current+$3 END),
           target=$4,
           updated_at=now()
     RETURNING current`,
    [userId, code, amount, target, options.absolute === true],
  );
  if ((row.rows[0]?.current ?? 0) < target) return false;
  return awardBadge(client, userId, code);
}

/// The daily chain. Returns the streak after today is counted.
///
/// A gap of one day continues the chain, anything longer starts it over - the
/// chain is the mechanic, and quietly forgiving a missed week would make it
/// meaningless. Called on any member action, so it has to be cheap and it has
/// to be safe to call twenty times a day.
export async function touchStreak(client: pg.PoolClient, userId: string): Promise<number> {
  await client.query('INSERT INTO member_scores(user_id) VALUES($1) ON CONFLICT DO NOTHING', [userId]);
  const row = await client.query<{ streak_days: number }>(
    `UPDATE member_scores
        SET streak_days = CASE
              WHEN last_active_on = CURRENT_DATE THEN streak_days
              WHEN last_active_on = CURRENT_DATE - 1 THEN streak_days + 1
              ELSE 1 END,
            streak_best = GREATEST(streak_best, CASE
              WHEN last_active_on = CURRENT_DATE THEN streak_days
              WHEN last_active_on = CURRENT_DATE - 1 THEN streak_days + 1
              ELSE 1 END),
            last_active_on = CURRENT_DATE,
            -- Coming back is what lifts a freeze. The perk was suspended for
            -- absence, so presence is the thing that ends it.
            perks_frozen_until = CASE WHEN perks_frozen_until <= now() THEN NULL ELSE perks_frozen_until END,
            updated_at = now()
      WHERE user_id=$1
      RETURNING streak_days`,
    [userId],
  );
  const streak = row.rows[0]?.streak_days ?? 1;
  for (const code of ['streak_master_14', 'streak_master_30', 'founding_architect'] as const) {
    await advanceProgress(client, userId, code, streak, { absolute: true });
  }
  return streak;
}

/// What a member's report is worth in the moderator queue.
///
/// Level 10 is Permanent Resident - roughly 1.350 XP, which is a member who has
/// been here a while and earned it. Below that a report is ordinary, which is
/// not an insult: it is the default, and the queue is worked in SLA order
/// regardless. A frozen account gets no priority no matter how many badges it
/// holds, otherwise the freeze would not be a freeze.
export async function reporterTrust(db: pg.Pool | pg.PoolClient, userId: string): Promise<'standard' | 'high'> {
  const row = await db.query<{ level: number; frozen: boolean }>(
    'SELECT level, (perks_frozen_until IS NOT NULL AND perks_frozen_until > now()) frozen FROM member_scores WHERE user_id=$1',
    [userId],
  );
  const score = row.rows[0];
  return score && !score.frozen && score.level >= 10 ? 'high' : 'standard';
}
