'use client';
import { cn } from '@/lib/cn';

/**
 * A phone-shaped frame around a live preview of what is being written.
 *
 * The composers had no preview at all, so an editor found out how a headline
 * wrapped, whether the summary fit the card, or that the body was one wall of
 * text, by publishing it and opening the app. The frame is deliberately the
 * app's own proportions and dark surface rather than a generic box: a preview
 * at desktop width would flatter every draft.
 *
 * It is a preview, not the app. The width, the type scale and the paragraph
 * rule are copied from the Flutter screens; anything that depends on real data
 * - reactions, comment counts, the reader's own state - is left out rather than
 * mocked up, because a fake "142 beğeni" under a draft teaches nothing.
 */
export function PhonePreview({ label, children, className }: { label?: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn('flex flex-col items-center', className)}>
      <div className="w-[300px] rounded-[2.25rem] border border-hairline bg-surface-raised p-2.5 shadow-2xl">
        <div className="relative h-[600px] overflow-hidden rounded-[1.75rem] bg-[#0b0a12]">
          {/* The notch is the only piece of chrome worth drawing: it is what
              tells you the top of a screen is partly covered. */}
          <div className="absolute top-2 left-1/2 z-10 h-5 w-24 -translate-x-1/2 rounded-full bg-surface-raised" />
          <div className="h-full overflow-y-auto pt-9 pb-6">{children}</div>
        </div>
      </div>
      {label && <p className="mt-3 text-xs text-ink-faint">{label}</p>}
    </div>
  );
}

/**
 * The app renders an article body as plain paragraphs split on a blank line -
 * see `news_article_screen.dart`. Splitting the same way here is the whole
 * point of the preview: it is the only place an editor can see that their
 * single-newline break will not become a paragraph.
 */
export function previewParagraphs(body: string): string[] {
  return body
    .split(/\n\s*\n/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph.length > 0);
}
