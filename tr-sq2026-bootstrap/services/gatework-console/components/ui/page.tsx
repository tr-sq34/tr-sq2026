import { cn } from '@/lib/cn';
import { Badge, type BadgeTone } from './badge';

/**
 * Page furniture: the header every section shares, and the two states a section
 * can be in when it has nothing to draw.
 *
 * `NotConnected` exists because this console has a standing rule that it never
 * invents a number. When a service is unreachable or a module has no backend
 * yet, the screen has to say which one and why - not render a zero. A stale "0
 * waiting" is read as "nothing to do", which is the most expensive wrong answer
 * a moderation queue can give.
 */
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  tone = 'brand',
}: {
  eyebrow: string;
  title: string;
  description?: string;
  actions?: React.ReactNode;
  tone?: BadgeTone;
}) {
  return (
    <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div className="min-w-0">
        <Badge tone={tone} dot>{eyebrow}</Badge>
        <h1 className="mt-3 text-2xl font-semibold tracking-tight text-ink">{title}</h1>
        {description && <p className="mt-2 max-w-2xl text-sm text-ink-muted">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </header>
  );
}

export function EmptyState({ icon: Icon, title, description, action, className }: {
  icon?: React.ComponentType<{ size?: number; className?: string }>;
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('rounded-card border border-dashed border-hairline bg-surface/50 px-6 py-14 text-center', className)}>
      {Icon && <Icon size={26} className="mx-auto text-ink-faint" />}
      <p className="mt-3 text-sm font-medium text-ink">{title}</p>
      {description && <p className="mx-auto mt-1.5 max-w-md text-sm text-ink-faint">{description}</p>}
      {action && <div className="mt-5 flex justify-center">{action}</div>}
    </div>
  );
}

export function NotConnected({ what, why }: { what: string; why: string }) {
  return (
    <div className="rounded-card border border-dashed border-warning/30 bg-warning-soft px-6 py-10">
      <Badge tone="warning" dot>Bağlanmadı</Badge>
      <p className="mt-3 text-sm font-medium text-ink">{what}</p>
      <p className="mt-1.5 max-w-xl text-sm text-ink-muted">{why}</p>
      <p className="mt-4 text-xs text-ink-faint">
        Bu alan sahte veri göstermez. İlgili servis ve denetim sözleşmesi etkinleştiğinde kendiliğinden dolar.
      </p>
    </div>
  );
}
