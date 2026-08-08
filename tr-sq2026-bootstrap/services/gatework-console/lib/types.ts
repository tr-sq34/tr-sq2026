export const gateworkRoles = ['owner', 'security_admin', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor'] as const;
export type GateworkRole = typeof gateworkRoles[number];

export type GateworkMember = {
  id: string;
  email: string;
  displayName: string;
  roles: GateworkRole[];
  stepUpAt?: string;
};
