'use client';
import { useMemo, useState } from 'react';
import { count, regionLabel, type LocationAnalytics } from '@/lib/analytics-labels';
import { cn } from '@/lib/cn';

/**
 * The state distribution, as a tile grid.
 *
 * Deliberately a cartogram and not a geographic map: every state is the same
 * square, so Rhode Island with 400 members is as readable as Texas with 40. A
 * real outline map would have made the biggest states look like the biggest
 * numbers, which is the opposite of what this screen is for. The arrangement is
 * approximate - it is a seating chart, not a border.
 *
 * The important rule is what an empty tile means. The service suppresses any
 * state under the threshold, so a state missing from `regions` is either empty
 * or too small to name, and the screen cannot tell which. Empty tiles therefore
 * read "boş ya da eşik altı" and never "0" - a zero here would be a claim the
 * data does not support.
 */
const GRID: (string | null)[][] = [
  ['AK', null, null, null, null, null, null, null, null, null, 'ME'],
  [null, null, null, null, null, null, null, null, null, 'VT', 'NH'],
  ['WA', 'ID', 'MT', 'ND', 'MN', 'IL', 'WI', 'MI', 'NY', 'RI', 'MA'],
  ['OR', 'NV', 'WY', 'SD', 'IA', 'IN', 'OH', 'PA', 'NJ', 'CT', null],
  ['CA', 'UT', 'CO', 'NE', 'MO', 'KY', 'WV', 'VA', 'MD', 'DC', null],
  [null, 'AZ', 'NM', 'KS', 'AR', 'TN', 'NC', 'SC', 'DE', null, null],
  [null, null, null, 'OK', 'LA', 'MS', 'AL', 'GA', null, null, null],
  ['HI', null, null, 'TX', null, null, null, 'FL', null, null, null],
];

const IN_GRID = new Set(GRID.flat().filter(Boolean) as string[]);
const STEPS = [0.14, 0.3, 0.48, 0.68, 0.9];

export function StateGrid({ locations }: { locations: LocationAnalytics }) {
  const [active, setActive] = useState<string | null>(null);

  const byCode = useMemo(
    () => new Map(locations.regions.map((row) => [row.regionCode, row])),
    [locations.regions],
  );
  const peak = Math.max(1, ...locations.regions.map((row) => row.members));
  // Codes the service reported that this grid has no square for - Porto Riko,
  // or anything a future release adds. Listed rather than dropped.
  const offGrid = locations.regions.filter((row) => !IN_GRID.has(row.regionCode));
  const selected = active ? byCode.get(active) ?? null : null;

  const shade = (members: number) => {
    const ratio = members / peak;
    const step = STEPS[Math.min(STEPS.length - 1, Math.floor(ratio * STEPS.length))];
    return `rgba(108, 92, 231, ${step})`;
  };

  return (
    <div>
      <div className="grid gap-1" style={{ gridTemplateColumns: 'repeat(11, minmax(0, 1fr))' }}>
        {GRID.flatMap((row, rowIndex) =>
          row.map((code, colIndex) => {
            if (!code) return <span key={`empty-${rowIndex}-${colIndex}`} aria-hidden />;
            const row_ = byCode.get(code);
            const known = row_ !== undefined;
            return (
              <button
                key={code}
                type="button"
                onClick={() => setActive((current) => (current === code ? null : code))}
                title={known ? `${regionLabel(code)} · ${count(row_.members)} üye` : `${regionLabel(code)} · boş ya da eşik altı`}
                style={known ? { backgroundColor: shade(row_.members) } : undefined}
                className={cn(
                  'aspect-square rounded-md text-[11px] font-semibold transition',
                  known ? 'text-white hover:ring-2 hover:ring-brand-300' : 'bg-surface-raised text-ink-faint hover:bg-surface-overlay',
                  active === code && 'ring-2 ring-brand-300',
                )}
              >
                {code}
              </button>
            );
          }),
        )}
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-ink-faint">
        <span className="flex items-center gap-1.5">
          az
          {STEPS.map((step) => <span key={step} className="size-3 rounded-sm" style={{ backgroundColor: `rgba(108, 92, 231, ${step})` }} />)}
          çok
        </span>
        <span className="flex items-center gap-1.5">
          <span className="size-3 rounded-sm bg-surface-raised" /> boş ya da eşik altı
        </span>
        <span>Kareler eşit büyüklüktedir; harita değil, dağılım şemasıdır.</span>
      </div>

      {selected ? (
        <p className="mt-3 rounded-lg border border-hairline bg-canvas px-4 py-3 text-sm text-ink-muted">
          <span className="font-medium text-ink">{regionLabel(selected.regionCode)}</span> · {count(selected.members)} üye
          {' · '}{count(selected.posts)} post{' · '}{count(selected.listings)} ilan
        </p>
      ) : (
        <p className="mt-3 text-xs text-ink-faint">Ayrıntı için bir eyalete tıkla.</p>
      )}

      {offGrid.length > 0 && (
        <p className="mt-2 text-xs text-ink-faint">
          Şemada karesi olmayan yerler: {offGrid.map((row) => `${regionLabel(row.regionCode)} (${count(row.members)})`).join(', ')}.
        </p>
      )}
    </div>
  );
}
