import { NextResponse, type NextRequest } from 'next/server';
import { gateworkMe, identityRefresh } from '@/lib/identity';
import {
  SESSION_COOKIE,
  SESSION_COOKIE_OPTIONS,
  accessTokenExpiry,
  decryptSession,
  encryptSession,
  type GateworkSession,
} from '@/lib/session';

/**
 * Keeps the operator's access token alive.
 *
 * The console signed operators in for eight hours on an access token that
 * Identity stops accepting after fifteen minutes, and never touched the refresh
 * token it was already storing. The panel therefore worked for a quarter of an
 * hour and then answered every screen with IDENTITY_401 while still looking
 * signed in. This runs before the render so a page never has to deal with a
 * token that died between navigations.
 *
 * It renews on the way in rather than reacting to a 401, because Identity
 * rotates refresh tokens: reusing a consumed one revokes the entire family and
 * signs the operator out for real. One renewal per request, decided from the
 * clock, is the only shape that stays away from that.
 *
 * Lives in `proxy.ts` rather than `middleware.ts`: Next 16 renamed the
 * convention and, with it, moved the default runtime to Node - which this needs
 * anyway, since the session cookie is AES-256-GCM from `node:crypto`.
 */
export const config = {
  // Everything a browser asks for on its own behalf. Static assets and the
  // Next.js internals carry no session and renewing on them would multiply
  // refresh calls by however many chunks a page happens to load.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|svg|ico|webp|woff2?)$).*)'],
};

/** Renew this long before the token actually dies, so a slow render still holds a live one. */
const RENEW_BEFORE_MS = 90_000;

/**
 * One renewal at a time per replica.
 *
 * A page load fires several requests at once - the document, its RSC payloads,
 * a fetch or two - and each of them passes through here. Without this they
 * would all present the same refresh token, Identity would see the second one
 * as a reuse of a consumed token, and it would revoke the family: the operator
 * gets signed out by the very thing meant to keep them signed in.
 */
const inFlight = new Map<string, Promise<GateworkSession | 'expired' | 'unavailable'>>();

async function renew(session: GateworkSession): Promise<GateworkSession | 'expired' | 'unavailable'> {
  const existing = inFlight.get(session.refreshToken);
  if (existing) return existing;

  const attempt = (async (): Promise<GateworkSession | 'expired' | 'unavailable'> => {
    const result = await identityRefresh(session.refreshToken);
    if (result.outcome === 'expired') return 'expired';
    if (result.outcome === 'unavailable') return 'unavailable';

    // Roles are re-read on every renewal instead of being carried over. An
    // operator whose Gatework access is taken away then loses the panel at the
    // next renewal rather than at the end of an eight hour cookie.
    let member = session.member;
    try {
      member = await gateworkMe(result.accessToken);
    } catch (error) {
      if (error instanceof Error && error.message === 'NOT_AUTHORIZED') return 'expired';
      // Identity answered the refresh but not the profile: keep the roles we
      // already had rather than throwing away a working session.
    }

    return {
      ...session,
      member,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      accessExpiresAt: accessTokenExpiry(result.accessToken),
    };
  })().finally(() => {
    inFlight.delete(session.refreshToken);
  });

  inFlight.set(session.refreshToken, attempt);
  return attempt;
}

/** Replace our cookie in the header the render will read, leaving the others alone. */
function rewriteCookieHeader(header: string | null, value: string) {
  const others = (header ?? '')
    .split(';')
    .map((part) => part.trim())
    .filter((part) => part.length > 0 && !part.startsWith(`${SESSION_COOKIE}=`));
  return [...others, `${SESSION_COOKIE}=${value}`].join('; ');
}

export default async function proxy(request: NextRequest) {
  const raw = request.cookies.get(SESSION_COOKIE)?.value;
  if (!raw) return NextResponse.next();

  const session = decryptSession(raw);
  // Unreadable or past its eight hours. The layout sends them to the sign-in
  // screen; there is nothing here to renew.
  if (!session) return NextResponse.next();

  const expiry = session.accessExpiresAt ?? accessTokenExpiry(session.accessToken);
  if (expiry !== undefined && expiry - Date.now() > RENEW_BEFORE_MS) return NextResponse.next();

  const renewed = await renew(session);

  // Identity is unreachable. The token in hand may still work, and if it does
  // not the screens say so - which beats signing an operator out over a blip.
  if (renewed === 'unavailable') return NextResponse.next();

  if (renewed === 'expired') {
    const response = NextResponse.next();
    response.cookies.delete(SESSION_COOKIE);
    return response;
  }

  const value = encryptSession(renewed);
  const headers = new Headers(request.headers);
  headers.set('cookie', rewriteCookieHeader(request.headers.get('cookie'), value));
  const response = NextResponse.next({ request: { headers } });
  response.cookies.set(SESSION_COOKIE, value, SESSION_COOKIE_OPTIONS);
  return response;
}
