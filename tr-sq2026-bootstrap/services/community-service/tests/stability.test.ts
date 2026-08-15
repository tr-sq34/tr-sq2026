import assert from 'node:assert/strict';
import test from 'node:test';
import { MIN_SESSIONS_FOR_RATE, crashFingerprint, crashFreeRate, redactCrashText } from '../src/stability.js';

test('an empty window has no rate at all, not a perfect one', () => {
  assert.equal(crashFreeRate({ sessions: 0, crashedSessions: 0 }), null);
  assert.equal(crashFreeRate({ sessions: MIN_SESSIONS_FOR_RATE - 1, crashedSessions: 0 }), null);
});

test('a rate is reported once the sample is big enough to mean something', () => {
  assert.equal(crashFreeRate({ sessions: 100, crashedSessions: 1 }), 99);
  assert.equal(crashFreeRate({ sessions: 1000, crashedSessions: 3 }), 99.7);
  assert.equal(crashFreeRate({ sessions: 20, crashedSessions: 20 }), 0);
});

test('the same bug on two devices is one group', () => {
  const android = crashFingerprint({
    errorType: 'NoSuchMethodError',
    message: "The method 'load' was called on null at 0x7f2a41",
    stack: 'package:america_hub/features/news/news_controller.dart 42:11\n#1 _AsyncAwait (dart:async)',
  });
  const ios = crashFingerprint({
    errorType: 'NoSuchMethodError',
    message: "The method 'load' was called on null at 0x91bc03",
    stack: 'package:america_hub/features/news/news_controller.dart 47:19\n#1 _AsyncAwait (dart:async)',
  });
  assert.equal(android, ios);
});

test('two different faults do not collapse into one row', () => {
  const news = crashFingerprint({
    errorType: 'StateError',
    message: 'Bad state: no element',
    stack: 'package:america_hub/features/news/news_controller.dart 42:11',
  });
  const forum = crashFingerprint({
    errorType: 'StateError',
    message: 'Bad state: no element',
    stack: 'package:america_hub/features/forum/forum_controller.dart 12:3',
  });
  assert.notEqual(news, forum);
});

test('a crash with no stack still groups by what it says', () => {
  const first = crashFingerprint({ errorType: 'DioException', message: 'Connection timed out' });
  const second = crashFingerprint({ errorType: 'DioException', message: 'Connection timed out' });
  assert.equal(first, second);
  assert.notEqual(first, crashFingerprint({ errorType: 'DioException', message: 'Bad certificate' }));
});

test('what a member typed does not get stored because an exception was holding it', () => {
  assert.match(redactCrashText('Invalid e-mail: ali@example.com'), /<e-posta>/);
  assert.doesNotMatch(redactCrashText('Invalid e-mail: ali@example.com'), /ali@example\.com/);

  const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.9wKcJq_signature';
  assert.doesNotMatch(redactCrashText(`401 with Bearer ${token}`), /eyJhbGci/);

  const sas = 'https://blob.core.windows.net/media/x.jpg?sv=2024-01-01&sig=abc123def';
  const redacted = redactCrashText(sas);
  assert.doesNotMatch(redacted, /abc123def/);
  assert.match(redacted, /sig=<gizli>/);
});
