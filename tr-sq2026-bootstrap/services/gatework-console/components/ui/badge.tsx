import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/cn';

/**
 * Status pill.
 *
 * The tones are the same four the app uses, and they are the only ones: a
 * status is neutral, good, worth a look, or bad. Screens that invented a fifth
 * colour - the old marketplace desk had a blue "under review" - made operators
 * learn a per-screen legend instead of reading the same four everywhere.
 */
const badge = cva(
  'inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium whitespace-nowrap',
  {
    variants: {
      tone: {
        neutral: 'bg-surface-overlay text-ink-muted',
        brand: 'bg-info-soft text-brand-300',
        success: 'bg-success-soft text-success',
        warning: 'bg-warning-soft text-warning',
        danger: 'bg-danger-soft text-danger',
      },
    },
    defaultVariants: { tone: 'neutral' },
  },
);

export type BadgeTone = NonNullable<VariantProps<typeof badge>['tone']>;

export function Badge({
  className,
  tone,
  dot = false,
  children,
  ...props
}: React.ComponentProps<'span'> & VariantProps<typeof badge> & { dot?: boolean }) {
  return (
    <span className={cn(badge({ tone }), className)} {...props}>
      {dot && <span className="size-1.5 rounded-full bg-current" aria-hidden />}
      {children}
    </span>
  );
}
