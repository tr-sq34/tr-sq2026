// What this file proves.
//
// The app refreshes its access token when - and only when - a request comes
// back 401. Every other status is treated as "the server answered, this is the
// answer". So a route that rejects an expired token with 400 does not just
// mislabel the failure: it takes away the one signal that would have fixed it.
// The member keeps tapping, every tap fails the same way, and closing and
// reopening the app is the only cure.
//
// This is not hypothetical. It is what happened to photo upload: the presign
// route caught the error `viewer()` throws (which carries no `statusCode`) and
// answered `statusCode ?? 400`. The token was an hour old, the upload was
// refused with MEDIA_UPLOAD_NOT_ACCEPTED, nothing refreshed, and the post went
// out without its photo.
//
// So: no route may turn a refused token into anything but a 401. No database
// needed - this is a property of the source.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const server = readFileSync(fileURLToPath(new URL('../src/server.ts', import.meta.url)), 'utf8');

const viewerSource = () => {
  const line = server.split('\n').find((candidate) => candidate.includes('async function viewer('));
  assert.ok(line, 'viewer() moved');
  return line;
};

test('viewer() still throws the bare error this whole rule is built on', () => {
  // If viewer() ever starts attaching a statusCode, the helpers below stop
  // being the thing that decides, and this file is testing nothing.
  assert.match(viewerSource(), /throw Error\('UNAUTHORIZED'\)/);
  assert.ok(
    !viewerSource().includes('statusCode'),
    'viewer() now carries a statusCode; the failure-status helpers need revisiting',
  );
});

test('a refused token is a 401 on write routes too', () => {
  assert.match(
    server,
    /const writeFailureStatus = \(error: unknown, fallback = 400\) =>[\s\S]{0,320}?'UNAUTHORIZED'[\s\S]{0,80}?401/,
    'writeFailureStatus no longer maps a refused token to 401',
  );
  assert.match(
    server,
    /const writeFailureStatus[\s\S]{0,320}?'FORBIDDEN'[\s\S]{0,80}?403/,
    'writeFailureStatus no longer maps a missing role to 403',
  );
});

test('no catch block sends a refused token back as a 400', () => {
  // These are the exact shapes that were in the file. Each one swallowed
  // UNAUTHORIZED into the 400 branch. Listing them by hand is deliberate: a
  // regex loose enough to catch "anything similar" would also catch the
  // correct ones and turn this test into noise.
  const swallowing = [
    '(error as { statusCode?: number }).statusCode ?? 400',
    "error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400",
    "(error as Error).message === 'FORBIDDEN' ? 403 : 400",
    "known === 'FORBIDDEN' ? 403 : 400",
  ];
  for (const shape of swallowing) {
    assert.ok(!server.includes(shape), `a route still answers an expired session with 400: ${shape}`);
  }
});

test('the three media routes are the ones that broke, so they are named here', () => {
  for (const route of [
    "app.post('/v1/media/uploads/presign'",
    "app.post('/v1/media/uploads/complete'",
    "app.get('/v1/media/:id'",
  ]) {
    const start = server.indexOf(route);
    assert.ok(start > 0, `route moved: ${route}`);
    const body = server.slice(start, start + 1400);
    assert.ok(
      body.includes('writeFailureStatus(error)'),
      `${route} does not use writeFailureStatus, so an expired token reads as a bad request`,
    );
  }
});
