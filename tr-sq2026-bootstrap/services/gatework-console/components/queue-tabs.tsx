'use client';
import { useState } from 'react';

/**
 * Two queues, one screen. The panels arrive as already-rendered children from
 * the server component so both lists are fetched in the same request the page
 * is: switching tabs is a local state flip, not a round trip, and a moderator
 * scanning for the urgent case does not pay for a fetch to find out a tab is
 * empty.
 *
 * Both panels stay mounted. Unmounting the hidden one would throw away the
 * selected report and any half-typed reason the moment someone glanced at the
 * other queue.
 */
export function QueueTabs({ tabs }: { tabs: { key: string; label: string; badge?: number; panel: React.ReactNode }[] }) {
  const [active, setActive] = useState(tabs[0]?.key ?? '');

  return (
    <>
      <div className="mb-5 flex flex-wrap gap-2">
        {tabs.map((tab) => (
          <button
            key={tab.key}
            type="button"
            onClick={() => setActive(tab.key)}
            className={`flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition ${active === tab.key ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'}`}
          >
            {tab.label}
            {tab.badge !== undefined && tab.badge > 0 && (
              <span className={`rounded px-1.5 py-0.5 text-[11px] font-semibold ${active === tab.key ? 'bg-zinc-950/20 text-zinc-950' : 'bg-zinc-700 text-zinc-200'}`}>{tab.badge}</span>
            )}
          </button>
        ))}
      </div>
      {tabs.map((tab) => (
        <div key={tab.key} hidden={active !== tab.key}>{tab.panel}</div>
      ))}
    </>
  );
}
