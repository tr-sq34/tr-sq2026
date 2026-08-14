'use client';
import * as TabsPrimitive from '@radix-ui/react-tabs';
import { cn } from '@/lib/cn';

/**
 * Tabs, with the row count carried on the trigger.
 *
 * Every queue in this console is "N waiting"; when the number lives in a
 * separate card the operator has to look in two places to decide which tab to
 * open. Radix rather than the hand-rolled buttons the desks used, because those
 * were `<button>` elements with no roving focus - unreachable by keyboard in
 * the order they appeared.
 */
export const Tabs = TabsPrimitive.Root;
export const TabsContent = TabsPrimitive.Content;

export function TabsList({ className, ...props }: React.ComponentProps<typeof TabsPrimitive.List>) {
  return (
    <TabsPrimitive.List
      className={cn('inline-flex flex-wrap items-center gap-1 rounded-xl border border-hairline bg-surface p-1', className)}
      {...props}
    />
  );
}

export function TabsTrigger({
  className,
  count,
  children,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Trigger> & { count?: number }) {
  return (
    <TabsPrimitive.Trigger
      className={cn(
        'group inline-flex items-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium text-ink-muted transition',
        'hover:text-ink data-[state=active]:bg-brand-500 data-[state=active]:text-white',
        className,
      )}
      {...props}
    >
      {children}
      {count !== undefined && (
        // The state lives on the trigger, so the count reads it through the
        // group rather than looking for a `data-state` of its own.
        <span className="rounded-full bg-surface-overlay px-1.5 py-0.5 text-[11px] text-ink-muted group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white">
          {count}
        </span>
      )}
    </TabsPrimitive.Trigger>
  );
}
