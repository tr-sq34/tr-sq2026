'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import {
  Activity, Award, BadgeCheck, CalendarDays, ChevronDown, GalleryVerticalEnd, Gavel, LayoutDashboard, LogOut, MapPinned,
  LifeBuoy, Megaphone, MessageSquare, MessagesSquare, Menu, Newspaper, Scale, ScrollText, ShieldAlert, Siren, Users, X,
} from 'lucide-react';
import { cn } from '@/lib/cn';
import type { NavGroup } from '@/lib/navigation';
import { Badge } from './ui/badge';

/**
 * Sidebar, top bar and the mobile drawer.
 *
 * Icons are resolved here rather than travelling with the navigation data,
 * because a React component is not serialisable across the server/client
 * boundary: the server decides which entries this operator may see, the client
 * decides what they look like.
 */
const ICONS: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  'command-center': LayoutDashboard,
  health: Activity,
  analytics: MapPinned,
  system: ScrollText,
  legal: Scale,
  content: GalleryVerticalEnd,
  news: Newspaper,
  forum: MessagesSquare,
  journey: Award,
  events: CalendarDays,
  members: Users,
  marketplace: Gavel,
  promotions: Megaphone,
  verification: BadgeCheck,
  moderation: ShieldAlert,
  communications: MessageSquare,
  safety: Siren,
  support: LifeBuoy,
};

function NavLink({ item, active, onNavigate }: { item: NavGroup['items'][number]; active: boolean; onNavigate: () => void }) {
  const Icon = ICONS[item.key] ?? LayoutDashboard;
  return (
    <Link
      href={item.href}
      onClick={onNavigate}
      aria-current={active ? 'page' : undefined}
      className={cn(
        'group flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition',
        active ? 'bg-brand-500/15 font-medium text-brand-200' : 'text-ink-muted hover:bg-surface-raised hover:text-ink',
      )}
    >
      <Icon size={17} className={active ? 'text-brand-300' : 'text-ink-faint group-hover:text-ink-muted'} />
      <span className="min-w-0 flex-1 truncate">{item.label}</span>
      {item.note && <Badge tone="warning" className="px-1.5 py-0.5 text-[10px]">{item.note}</Badge>}
    </Link>
  );
}

function Nav({ groups, pathname, onNavigate }: { groups: NavGroup[]; pathname: string; onNavigate: () => void }) {
  // Groups start open. Collapsing is there for an operator who lives in one
  // section all day, not a default that hides half the console on first login.
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  return (
    <nav className="grid gap-5">
      {groups.map((group) => {
        const isCollapsed = collapsed[group.key] ?? false;
        return (
          <div key={group.key}>
            <button
              type="button"
              onClick={() => setCollapsed((current) => ({ ...current, [group.key]: !isCollapsed }))}
              aria-expanded={!isCollapsed}
              className="mb-1.5 flex w-full items-center justify-between gap-2 px-3 text-[11px] font-semibold tracking-[.12em] text-ink-faint uppercase transition hover:text-ink-muted"
            >
              {group.label}
              <ChevronDown size={13} className={cn('transition-transform', isCollapsed && '-rotate-90')} />
            </button>
            {!isCollapsed && (
              <div className="grid gap-0.5">
                {group.items.map((item) => (
                  <NavLink
                    key={item.key}
                    item={item}
                    active={pathname === item.href || pathname.startsWith(`${item.href}/`)}
                    onNavigate={onNavigate}
                  />
                ))}
              </div>
            )}
          </div>
        );
      })}
    </nav>
  );
}

export function AppFrame({
  groups,
  displayName,
  roleLabels,
  children,
}: {
  groups: NavGroup[];
  displayName: string;
  roleLabels: string[];
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  // The mobile drawer covers the page it navigates to, so it has to close on
  // arrival; without this the operator taps a section and sees the menu again.
  useEffect(() => setDrawerOpen(false), [pathname]);

  const current = groups.flatMap((group) => group.items).find((item) => pathname.startsWith(item.href));

  async function signOut() {
    setSigningOut(true);
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
    } finally {
      // Refresh rather than push: the cookie is gone, so the layout's own
      // redirect is what decides where an unauthenticated operator lands.
      router.replace('/');
      router.refresh();
    }
  }

  const aside = (
    <>
      <div className="mb-7 flex items-center justify-between gap-2 px-3">
        <div>
          <p className="text-[11px] font-semibold tracking-[.2em] text-brand-400 uppercase">TurkSquare</p>
          <p className="mt-0.5 text-lg font-semibold text-ink">Gatework</p>
        </div>
        <button
          type="button"
          onClick={() => setDrawerOpen(false)}
          aria-label="Menüyü kapat"
          className="rounded-lg p-1.5 text-ink-faint transition hover:bg-surface-raised hover:text-ink lg:hidden"
        >
          <X size={18} />
        </button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto pb-4">
        <Nav groups={groups} pathname={pathname} onNavigate={() => setDrawerOpen(false)} />
      </div>
      <div className="border-t border-hairline px-3 pt-4">
        <p className="truncate text-sm font-medium text-ink">{displayName}</p>
        <p className="mt-0.5 truncate text-xs text-ink-faint">{roleLabels.join(' · ')}</p>
        <button
          type="button"
          onClick={() => void signOut()}
          disabled={signingOut}
          className="mt-3 flex w-full items-center gap-2 rounded-lg px-2 py-2 text-sm text-ink-muted transition hover:bg-surface-raised hover:text-danger disabled:opacity-40"
        >
          <LogOut size={16} />
          {signingOut ? 'Çıkılıyor…' : 'Oturumu kapat'}
        </button>
      </div>
    </>
  );

  return (
    <div className="min-h-screen lg:grid lg:grid-cols-[264px_1fr]">
      <aside className="sticky top-0 hidden h-screen flex-col border-r border-hairline bg-surface p-4 lg:flex">{aside}</aside>

      {drawerOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button type="button" aria-label="Menüyü kapat" onClick={() => setDrawerOpen(false)} className="absolute inset-0 bg-canvas/80 backdrop-blur-sm" />
          <div className="relative flex h-full w-72 max-w-[85vw] flex-col border-r border-hairline bg-surface p-4 [animation:gatework-fade-in_.15s_ease-out]">{aside}</div>
        </div>
      )}

      <div className="min-w-0">
        <header className="sticky top-0 z-30 flex items-center gap-3 border-b border-hairline bg-canvas/90 px-4 py-3 backdrop-blur lg:px-8">
          <button
            type="button"
            onClick={() => setDrawerOpen(true)}
            aria-label="Menüyü aç"
            className="rounded-lg p-2 text-ink-muted transition hover:bg-surface-raised hover:text-ink lg:hidden"
          >
            <Menu size={18} />
          </button>
          <p className="min-w-0 flex-1 truncate text-sm font-medium text-ink-muted">{current?.label ?? 'Gatework'}</p>
          <span className="hidden text-xs text-ink-faint sm:inline">{displayName}</span>
        </header>
        <main className="p-4 lg:p-8">{children}</main>
      </div>
    </div>
  );
}
