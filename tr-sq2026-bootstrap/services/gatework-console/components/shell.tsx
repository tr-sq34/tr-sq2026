import { navigationFor, ROLE_LABELS } from '@/lib/navigation';
import type { GateworkMember } from '@/lib/types';
import { AppFrame } from './app-frame';

/**
 * Server half of the frame: it resolves which sections this operator's roles
 * allow, then hands the frame plain data. Nothing role-related is decided in
 * the browser, so a menu entry cannot be brought back by editing state.
 */
export function Shell({ member, children }: { member: GateworkMember; children: React.ReactNode }) {
  return (
    <AppFrame
      groups={navigationFor(member.roles)}
      displayName={member.displayName}
      roleLabels={member.roles.map((role) => ROLE_LABELS[role] ?? role)}
    >
      {children}
    </AppFrame>
  );
}
