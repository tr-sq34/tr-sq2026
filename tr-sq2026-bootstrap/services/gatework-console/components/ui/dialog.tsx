'use client';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { cn } from '@/lib/cn';

/**
 * Centred modal, used for confirmations that need a typed reason.
 *
 * This replaces `window.prompt`, which several desks still used to collect
 * cancellation and takedown reasons. A native prompt cannot show what is about
 * to happen, cannot enforce the minimum length the API requires, and renders
 * outside the page - so the operator confirmed a destructive action against a
 * grey box with no record of which row they were on.
 */
export const Dialog = DialogPrimitive.Root;
export const DialogTrigger = DialogPrimitive.Trigger;
export const DialogClose = DialogPrimitive.Close;

export function DialogContent({
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
          'fixed top-1/2 left-1/2 z-50 w-[calc(100vw-2rem)] max-w-lg -translate-x-1/2 -translate-y-1/2 rounded-card border border-hairline bg-surface shadow-2xl [animation:gatework-zoom-in_.15s_ease-out]',
          className,
        )}
        {...props}
      >
        <div className="flex items-start justify-between gap-4 p-5 pb-0">
          <div className="min-w-0">
            <DialogPrimitive.Title className="text-base font-semibold text-ink">{title}</DialogPrimitive.Title>
            {description
              ? <DialogPrimitive.Description className="mt-1 text-sm text-ink-muted">{description}</DialogPrimitive.Description>
              : <DialogPrimitive.Description className="sr-only">{title}</DialogPrimitive.Description>}
          </div>
          <DialogPrimitive.Close
            aria-label="Kapat"
            className="rounded-lg p-1.5 text-ink-faint transition hover:bg-surface-overlay hover:text-ink"
          >
            <X size={18} />
          </DialogPrimitive.Close>
        </div>
        {children}
      </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
  );
}

export function DialogBody({ className, ...props }: React.ComponentProps<'div'>) {
  return <div className={cn('p-5', className)} {...props} />;
}

export function DialogFooter({ className, ...props }: React.ComponentProps<'div'>) {
  return <div className={cn('flex flex-wrap justify-end gap-2 border-t border-hairline p-4', className)} {...props} />;
}
