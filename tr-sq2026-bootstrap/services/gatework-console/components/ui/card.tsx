import { cn } from '@/lib/cn';

/**
 * The panel's single container.
 *
 * Before this existed every screen wrote its own `rounded-xl border
 * border-white/10 bg-zinc-900/40 p-4`, and they had drifted: four different
 * radii, three different border opacities and two padding scales across the
 * fourteen sections. One component means fixing the surface once.
 */
export function Card({
  className,
  tone = 'default',
  ...props
}: React.ComponentProps<'div'> & { tone?: 'default' | 'raised' | 'urgent' }) {
  return (
    <div
      className={cn(
        'rounded-card border',
        tone === 'urgent'
          ? 'border-danger/40 bg-danger-soft'
          : tone === 'raised'
            ? 'border-hairline bg-surface-raised'
            : 'border-hairline bg-surface',
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: React.ComponentProps<'div'>) {
  return <div className={cn('flex items-start justify-between gap-4 p-5 pb-0', className)} {...props} />;
}

export function CardTitle({ className, ...props }: React.ComponentProps<'h2'>) {
  return <h2 className={cn('text-sm font-semibold text-ink', className)} {...props} />;
}

export function CardDescription({ className, ...props }: React.ComponentProps<'p'>) {
  return <p className={cn('mt-1 text-xs text-ink-faint', className)} {...props} />;
}

export function CardContent({ className, ...props }: React.ComponentProps<'div'>) {
  return <div className={cn('p-5', className)} {...props} />;
}

export function CardFooter({ className, ...props }: React.ComponentProps<'div'>) {
  return <div className={cn('flex flex-wrap items-center gap-2 border-t border-hairline p-4', className)} {...props} />;
}
