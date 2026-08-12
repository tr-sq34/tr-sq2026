import Link from 'next/link';
import { Activity, BadgeCheck, ClipboardList, GalleryVerticalEnd, Gavel, MapPinned, Megaphone, MessageSquare, Newspaper, ShieldAlert, Users, Workflow } from 'lucide-react';
import type { GateworkMember } from '@/lib/types';

const items = [
  ['Komuta Merkezi', '/command-center', Activity], ['İçerik Stüdyosu', '/content', GalleryVerticalEnd], ['Haber Merkezi', '/news', Newspaper], ['Tanıtımlar', '/promotions', Megaphone], ['Üyeler', '/members', Users], ['Moderasyon', '/moderation', ShieldAlert], ['Çarşı ve İhaleler', '/marketplace', Gavel], ['Mesajlar ve Forum', '/communications', MessageSquare], ['Güvenlik ve SOS', '/safety', Workflow], ['Analitik ve Konum', '/analytics', MapPinned], ['Doğrulama', '/verification', BadgeCheck], ['Sistem ve Denetim', '/system', ClipboardList],
] as const;

export function Shell({ member, children }: { member: GateworkMember; children: React.ReactNode }) {
  return <div className="min-h-screen bg-zinc-950 text-zinc-100 md:grid md:grid-cols-[250px_1fr]"><aside className="border-b border-white/10 bg-zinc-950 p-5 md:min-h-screen md:border-b-0 md:border-r"><div className="mb-8"><p className="text-xs font-semibold uppercase tracking-[.2em] text-emerald-400">TurkSquare</p><p className="mt-1 text-xl font-semibold">Gatework</p></div><nav className="grid gap-1">{items.map(([label, href, Icon]) => <Link key={href} href={href} className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-zinc-300 transition hover:bg-zinc-800 hover:text-white"><Icon size={17} />{label}</Link>)}</nav><div className="mt-8 border-t border-white/10 pt-4 text-xs text-zinc-500"><p className="font-medium text-zinc-300">{member.displayName}</p><p>{member.roles.join(' · ')}</p></div></aside><section className="min-w-0 p-6 md:p-10">{children}</section></div>;
}
