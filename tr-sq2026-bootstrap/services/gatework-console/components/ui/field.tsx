'use client';
import { cn } from '@/lib/cn';

/**
 * Form controls.
 *
 * The composers each declared a local `const field = 'rounded-lg border ...'`
 * string and passed it around by hand, so a field added later in the same form
 * routinely missed the focus ring. The ring is the point: it is the only signal
 * that says which box a keystroke is going into.
 */
const control =
  'w-full rounded-lg border border-hairline bg-canvas px-3 py-2 text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-brand-400 disabled:opacity-40';

export function Field({
  label,
  hint,
  error,
  className,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <label className={cn('block text-sm', className)}>
      <span className="mb-1.5 block font-medium text-ink-muted">{label}</span>
      {children}
      {/* An error replaces the hint rather than stacking under it: two lines of
          guidance where one contradicts the other is worse than either alone. */}
      {error ? (
        <span className="mt-1.5 block text-xs text-danger">{error}</span>
      ) : hint ? (
        <span className="mt-1.5 block text-xs text-ink-faint">{hint}</span>
      ) : null}
    </label>
  );
}

export function Input({ className, ...props }: React.ComponentProps<'input'>) {
  return <input className={cn(control, className)} {...props} />;
}

export function Textarea({ className, ...props }: React.ComponentProps<'textarea'>) {
  return <textarea className={cn(control, 'resize-y', className)} {...props} />;
}

export function Select({ className, ...props }: React.ComponentProps<'select'>) {
  return <select className={cn(control, 'appearance-none pr-8', className)} {...props} />;
}
