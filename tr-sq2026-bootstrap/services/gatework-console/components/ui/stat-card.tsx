import Link from 'next/link';
import { ArrowUpRight } from 'lucide-react';
import { cn } from '@/lib/cn';
import { Badge, type BadgeTone } from './badge';

/**
 * The dashboard number.
 *
 * `value` is a string, not a number, because half of these are not numbers:
 * a card whose service did not answer has to say so in the same slot, and a
 * card that reads "-" is indistinguishable from one that genuinely counted
 * nothing. `unavailable` makes that distinction visible instead of leaving it
 * to whoever writes the string.
 */
export function StatCard({
  label,
  value,
  detail,
  icon: Icon,
  tone = 'neutral',
  badge,
  href,
  unavailable = false,
}: {
  label: string;
  value: string;
  detail?: string;
  icon?: React.ComponentType<{ size?: number; className?: string }>;
  tone?: BadgeTone;
  badge?: string;
  href?: string | null;
  unavailable?: boolean;
}) {
  const accent = {
    neutral: 'text-ink-muted',
    brand: 'text-brand-300',
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
  }[tone];

  const body = (
    <article
      className={cn(
        'group h-full rounded-card border p-5 transition',
        tone === 'danger' ? 'border-danger/40 bg-danger-soft' : 'border-hairline bg-surface',
        href && 'hover:border-brand-400/50',
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <span className="text-xs font-medium tracking-wide text-ink-faint uppercase">{label}</span>
        {Icon && <Icon size={17} className={accent} />}
      </div>
      <p className={cn('mt-4 text-2xl font-semibold tracking-tight', unavailable ? 'text-ink-faint' : 'text-ink')}>{value}</p>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        {badge && <Badge tone={tone}>{badge}</Badge>}
        {detail && <span className="text-xs text-ink-faint">{detail}</span>}
      </div>
      {href && (
        <span className="mt-4 inline-flex items-center gap-1 text-xs text-ink-faint transition group-hover:text-brand-300">
          Aç <ArrowUpRight size={12} />
        </span>
      )}
    </article>
  );

  return href ? <Link href={href} className="block">{body}</Link> : body;
}
