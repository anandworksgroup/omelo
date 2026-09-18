import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

// /auth covers /auth/callback and /auth/reset (the recovery link lands there
// signed out, before the code exchange).
const PUBLIC_PATHS = ['/', '/sign-in', '/sign-up', '/forgot-password', '/auth'];

/**
 * Refreshes the Supabase session on every request and gates the dashboard.
 *
 * This is convenience routing, not security. The real boundary is RLS plus
 * the server client running as the signed-in user — a bypassed middleware
 * still cannot read another company's data.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isPublic = PUBLIC_PATHS.some(
    (p) => path === p || path.startsWith(p + '/')
  );

  if (!user && !isPublic) {
    // Keep the full return path (e.g. /meet/<room> from an invitation or a
    // "Candidate is waiting" notification) so sign-in lands back there.
    const url = request.nextUrl.clone();
    url.pathname = '/sign-in';
    url.search = '';
    url.searchParams.set('next', path + request.nextUrl.search);
    return NextResponse.redirect(url);
  }

  if (user && (path === '/sign-in' || path === '/sign-up')) {
    const url = request.nextUrl.clone();
    url.pathname = '/dashboard';
    url.search = '';
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
