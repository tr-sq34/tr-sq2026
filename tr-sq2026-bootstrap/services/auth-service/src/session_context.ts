/**
 * Oturumun geldigi cihaz ve ag blogu.
 *
 * Yenileme jetonu ailesi zaten bir oturum; eksik olan, o oturumun kime ait
 * oldugunu insanin taniyabilecegi bir iz birakmasiydi. "Uc acik oturumun var"
 * cumlesi, iclerinden birinin baskasina ait oldugunu fark etmeye yetmiyor.
 */

export interface SessionContext {
  userAgent: string | null;
  ipPrefix: string | null;
}

/// Tarayici/uygulama imzasi uzun olabiliyor ve satirin isi kimlik taramak degil,
/// taninabilir bir etiket birakmak. Sinirin uzerini kesmek, uzun bir imzayla
/// satiri sisirmeye yegdir.
const MAX_USER_AGENT = 200;

/**
 * IP'nin blogu: IPv4'te /24, IPv6'da /48.
 *
 * Tam adres saklanmiyor. "Bu oturum hep ayni yerden mi geliyor" sorusunun
 * cevabi blokta duruyor; adresin tamami ise uyenin nerede oldugunun gun gun
 * kaydi olurdu ve bu, guvenlik ekraninin sormadigi bir soru.
 */
export function ipPrefixOf(value: string | null | undefined): string | null {
  const ip = value?.trim();
  if (!ip) return null;

  // IPv4 - ve IPv4-mapped IPv6 ("::ffff:203.0.113.42"), ki o da bir IPv4.
  const asIpv4 = ip.includes('.') ? ip.slice(ip.lastIndexOf(':') + 1) : null;
  if (asIpv4) {
    const octets = asIpv4.split('.');
    if (octets.length !== 4 || octets.some((octet) => !/^\d{1,3}$/.test(octet) || Number(octet) > 255)) return null;
    return `${octets[0]}.${octets[1]}.${octets[2]}.0/24`;
  }

  if (!ip.includes(':')) return null;
  // "2001:db8::1" bolununce ['2001','db8','','1'] veriyor: bostaki grup,
  // sikistirmanin orada basladigini yani o grubun sifir oldugunu soyluyor.
  const groups = ip.split(':').slice(0, 3);
  if (groups.length < 3) return null;
  const normalised = groups.map((group) => (group === '' ? '0' : group));
  if (normalised.some((group) => !/^[0-9a-fA-F]{1,4}$/.test(group))) return null;
  return `${normalised.join(':').toLowerCase()}::/48`;
}

const headerValue = (value: string | string[] | undefined) =>
  (Array.isArray(value) ? value[0] : value)?.trim() || null;

/**
 * Istekten oturum izini cikarir.
 *
 * Adres once Cloudflare'in yazdigi basliktan okunuyor: uygulama Container
 * Apps'in arkasinda, dolayisiyla soketin gordugu adres her zaman ic aginki.
 * Basliklarin hicbiri yoksa alan bos kaliyor - bilinmeyen bir adres yerine
 * soketinkini yazmak, ekranda gercek sanilacak bir sey gostermek olurdu.
 */
export function sessionContextOf(request: {
  headers: Record<string, string | string[] | undefined>;
  ip?: string;
}): SessionContext {
  const forwarded = headerValue(request.headers['x-forwarded-for'])?.split(',')[0];
  const address = headerValue(request.headers['cf-connecting-ip']) ?? forwarded?.trim() ?? null;
  const agent = headerValue(request.headers['user-agent']);
  return {
    userAgent: agent ? agent.slice(0, MAX_USER_AGENT) : null,
    ipPrefix: ipPrefixOf(address),
  };
}
