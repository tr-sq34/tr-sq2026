import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { Shell } from '@/components/shell';

export const dynamic = 'force-dynamic';
export default async function AppLayout({ children }: { children: React.ReactNode }) { const session = await getSession(); if (!session) redirect('/'); return <Shell member={session.member}>{children}</Shell>; }
