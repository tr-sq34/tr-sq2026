'use client';
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/cn';

/**
 * Actions in this console suspend accounts, take content down and open a
 * member's location record. `danger` is therefore a real variant rather than a
 * red utility class someone remembered to add: a destructive action should be
 * impossible to build here without it looking destructive.
 */
const button = cva(
  'inline-flex items-center justify-center gap-2 rounded-lg font-medium whitespace-nowrap transition disabled:pointer-events-none disabled:opacity-40',
  {
    variants: {
      variant: {
        primary: 'bg-brand-500 text-white hover:bg-brand-400',
        secondary: 'bg-surface-overlay text-ink hover:bg-hairline',
        outline: 'border border-hairline text-ink-muted hover:border-brand-400/50 hover:text-ink',
        ghost: 'text-ink-muted hover:bg-surface-overlay hover:text-ink',
        danger: 'border border-danger/40 bg-danger-soft text-danger hover:bg-danger/20',
        success: 'border border-success/40 bg-success-soft text-success hover:bg-success/20',
      },
      size: {
        sm: 'h-8 px-3 text-xs',
        md: 'h-10 px-4 text-sm',
        icon: 'size-9',
      },
    },
    defaultVariants: { variant: 'secondary', size: 'md' },
  },
);

export function Button({
  className,
  variant,
  size,
  asChild = false,
  ...props
}: React.ComponentProps<'button'> & VariantProps<typeof button> & { asChild?: boolean }) {
  const Component = asChild ? Slot : 'button';
  return <Component className={cn(button({ variant, size }), className)} {...props} />;
}

export { button as buttonStyles };
