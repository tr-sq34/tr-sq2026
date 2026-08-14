import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * Joins class names and lets a caller's classes win over a component's own.
 *
 * Without the merge step `<Card className="p-0">` would produce `p-5 p-0` and
 * the winner would depend on the order Tailwind happened to emit the two rules
 * in, which is not something a screen author should have to reason about.
 */
export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
