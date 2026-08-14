'use client';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { cn } from '@/lib/cn';

/**
 * The right-hand detail panel.
 *
 * Members, reports and listings are all "a list you scan, one row you work on".
 * The old screens answered that with a separate page per row, which lost the
 * queue position on every back navigation - an operator working a moderation
 * backlog had to find their place again after every decision. A sheet keeps the
 * list underneath.
 */
export const Sheet = DialogPrimitive.Root;
export const SheetTrigger = DialogPrimitive.Trigger;
export const SheetClose = DialogPrimitive.Close;

export function SheetContent({
  className,
  children,
  title,
  description,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & { title: string; description?: string }) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-canvas/80 [animation:gatework-fade-in_.15s_ease-out] backdrop-blur-sm" />
      <DialogPrimitive.Content
        className={cn(
          'fixed inset-y-0 right-0 z-50 flex w-full max-w-xl flex-col border-l border-hairline bg-surface shadow-2xl [animation:gatework-slide-in-right_.2s_ease-out]',
          className,
        )}
        {...props}
      >
        <div className="flex items-start justify-between gap-4 border-b border-hairline p-5">
          <div className="min-w-0">
            <DialogPrimitive.Title className="truncate text-base font-semibold text-ink">{title}</DialogPrimitive.Title>
            {description
              ? <DialogPrimitive.Description className="mt-1 text-xs text-ink-faint">{description}</DialogPrimitive.Description>
              // Radix warns when a dialog has no description; an empty one that
              // screen readers skip is better than a sentence invented per screen.
              : <DialogPrimitive.Description className="sr-only">Detay paneli</DialogPrimitive.Description>}
          </div>
          <DialogPrimitive.Close
            aria-label="Paneli kapat"
            className="rounded-lg p-1.5 text-ink-faint transition hover:bg-surface-overlay hover:text-ink"
          >
            <X size={18} />
          </DialogPrimitive.Close>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
      </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
  );
}
