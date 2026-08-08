import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { LoginForm } from '@/components/login-form';

export const dynamic = 'force-dynamic';
export default async function Entry() {
  if (await getSession()) redirect('/command-center');
  return <main className="grid min-h-screen place-items-center bg-[radial-gradient(circle_at_top,#164e63_0%,#09090b_44%)] p-6"><LoginForm /></main>;
}
