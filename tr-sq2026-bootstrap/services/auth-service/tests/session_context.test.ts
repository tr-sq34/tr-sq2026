// Bu dosyanin ispat ettigi sey.
//
// Oturum satirina yazilan ag blogu, adresin kendisi degil. Kod bir kez yanlis
// keserse ekranda yine makul gorunen bir sey cikar - "203.0.113.42/24" da bir
// sey soyluyormus gibi durur - ama saklanmayacagi soylenen bilgi saklanmis
// olur. Bu yuzden kesme kurali gozle degil testle tutuluyor.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { ipPrefixOf, sessionContextOf } from '../src/session_context.ts';

test('IPv4 adresin son hanesi saklanmiyor', () => {
  assert.equal(ipPrefixOf('203.0.113.42'), '203.0.113.0/24');
  assert.equal(ipPrefixOf(' 10.1.2.3 '), '10.1.2.0/24');
});

test('IPv4-mapped IPv6 de bir IPv4 olarak kesiliyor', () => {
  // Container Apps'in arkasindan bu bicimde gelebiliyor; IPv6 gibi islenirse
  // adresin tamami satira yazilirdi.
  assert.equal(ipPrefixOf('::ffff:203.0.113.42'), '203.0.113.0/24');
});

test('IPv6 adres /48 blogu olarak kesiliyor', () => {
  assert.equal(ipPrefixOf('2001:0db8:85a3:0000:0000:8a2e:0370:7334'), '2001:0db8:85a3::/48');
  // Sikistirilmis bicimde bos grup, orada sifir oldugu anlamina geliyor.
  assert.equal(ipPrefixOf('2001:db8::1'), '2001:db8:0::/48');
});

test('adres okunamiyorsa satira bir sey yazilmiyor', () => {
  // Uydurulmus bir blok, hicbir sey yazmamaktan daha kotu: ekranda gercek
  // saniliyor.
  for (const value of [null, undefined, '', 'bilinmiyor', '999.1.1.1', '10.0.0']) {
    assert.equal(ipPrefixOf(value), null, `${value} icin blok uretildi`);
  }
});

test('adres once Cloudflare basligindan okunuyor', () => {
  const context = sessionContextOf({
    headers: {
      'cf-connecting-ip': '203.0.113.42',
      'x-forwarded-for': '198.51.100.7, 10.0.0.1',
      'user-agent': 'AmericaHub/1.0 (Android 14)',
    },
    ip: '10.0.0.1',
  });

  assert.equal(context.ipPrefix, '203.0.113.0/24');
  assert.equal(context.userAgent, 'AmericaHub/1.0 (Android 14)');
});

test('Cloudflare basligi yoksa zincirin ilk adresi okunuyor', () => {
  const context = sessionContextOf({
    headers: { 'x-forwarded-for': '198.51.100.7, 10.0.0.1' },
    ip: '10.0.0.1',
  });

  assert.equal(context.ipPrefix, '198.51.100.0/24');
  assert.equal(context.userAgent, null);
});

test('hicbir baslik yoksa ic agin adresi yazilmiyor', () => {
  // request.ip her zaman dolu ama her zaman ic agdan: onu yazmak, listede
  // butun oturumlarin ayni yerden geldigini gostermek olurdu.
  const context = sessionContextOf({ headers: {}, ip: '10.0.0.1' });

  assert.equal(context.ipPrefix, null);
  assert.equal(context.userAgent, null);
});

test('cok uzun cihaz imzasi satiri sismiyor', () => {
  const context = sessionContextOf({ headers: { 'user-agent': 'M'.repeat(500) }, ip: '' });

  assert.equal(context.userAgent?.length, 200);
});
