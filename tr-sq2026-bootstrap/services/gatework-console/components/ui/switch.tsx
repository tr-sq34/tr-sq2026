'use client';
import * as SwitchPrimitive from '@radix-ui/react-switch';
import { cn } from '@/lib/cn';

/**
 * Role and capability toggles.
 *
 * Roles were granted through a checkbox that submitted a whole form, so the
 * operator could not tell which of six toggles their save had actually changed.
 * A switch commits one grant at a time, which is also how the audit record
 * reads it - one entry per capability, not one per form.
 */
export function Switch({
  label,
  hint,
  className,
  ...props
}: React.ComponentProps<typeof SwitchPrimitive.Root> & { label: string; hint?: string }) {
  return (
    <label className={cn('flex items-start justify-between gap-4 py-2.5', className)}>
      <span className="min-w-0">
        <span className="block text-sm text-ink">{label}</span>
        {hint && <span className="mt-0.5 block text-xs text-ink-faint">{hint}</span>}
      </span>
      <SwitchPrimitive.Root
        className="relative mt-0.5 h-5 w-9 shrink-0 rounded-full border border-hairline bg-surface-overlay transition data-[state=checked]:border-brand-500 data-[state=checked]:bg-brand-500 disabled:opacity-40"
        {...props}
      >
        <SwitchPrimitive.Thumb className="block size-3.5 translate-x-0.5 rounded-full bg-ink-muted transition-transform data-[state=checked]:translate-x-[18px] data-[state=checked]:bg-white" />
      </SwitchPrimitive.Root>
    </label>
  );
}
