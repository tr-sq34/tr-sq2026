/**
 * Acilis kartlarinin gorsellerini uretir.
 *
 * Ana sayfanin en ustundeki Story seridi, yeni bir uyenin agi bos oldugu icin
 * ilk gun hic cizilmiyordu. Serit orada duran ilk sey oldugu icin de uygulama
 * bos bir ekranla aciliyordu. Bu dort kart platformun kendi kartlari: bir
 * reklam degiller, uygulamanin ne yaptigini anlatiyorlar ve `035` gecisi
 * onlari 'story_slot' yuvasina yerlestiriyor.
 *
 * Gorseller depoya islenmis JPEG'ler. Uretim sirasinda bir blob yuklemesi
 * gerekmesin diye boyle: gecis yalnizca SQL calistirabilir, blob kimlik
 * bilgileri de gecis isinde yok. Servis bunlari /v1/public/launch altindan
 * kendisi sunuyor.
 *
 * Calistirmak icin:  node scripts/render_launch_cards.mjs
 * (sharp zaten medya isleyicinin bagimliligi, ek kurulum yok.)
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const OUT = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'launch');

// 1080x1920: Story tam ekran acildiginda telefonun orani. Serit ise ayni
// gorseli 52 piksellik bir daireye kirpiyor, o yuzden her kartin ortasinda
// tek basina anlamli bir amblem var - basligin ortasindan kesilmis bir daire
// serit icin ise yaramaz.
const W = 1080;
const H = 1920;
const CENTER_Y = 960;

const escape = (value) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const lines = (text, y, size, weight, opacity) =>
  text
    .split('\n')
    .map(
      (line, index) =>
        `<text x="${W / 2}" y="${y + index * (size * 1.28)}" text-anchor="middle" font-family="Segoe UI, Noto Sans, DejaVu Sans, sans-serif" font-size="${size}" font-weight="${weight}" fill="#ffffff" fill-opacity="${opacity}">${escape(line)}</text>`,
    )
    .join('');

/// Amblemler yazi tipine bagli degil: hepsi cizgi ve daire. Bir sunucuda
/// yaziyi ceviren font eksik olsa bile kartin ortasi bos kalmasin diye.
const EMBLEMS = {
  monogram: `
    <text x="${W / 2}" y="${CENTER_Y + 62}" text-anchor="middle" font-family="Segoe UI, Noto Sans, DejaVu Sans, sans-serif" font-size="180" font-weight="700" fill="#ffffff">TS</text>`,
  bag: `
    <g transform="translate(${W / 2 - 110}, ${CENTER_Y - 120})" fill="none" stroke="#ffffff" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">
      <path d="M20 70 h180 l16 170 a12 12 0 0 1 -12 13 h-188 a12 12 0 0 1 -12 -13 z" />
      <path d="M74 92 v-30 a36 36 0 0 1 72 0 v30" />
    </g>`,
  speech: `
    <g transform="translate(${W / 2 - 115}, ${CENTER_Y - 115})" fill="none" stroke="#ffffff" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">
      <path d="M24 40 h182 a24 24 0 0 1 24 24 v112 a24 24 0 0 1 -24 24 h-96 l-62 52 v-52 h-24 a24 24 0 0 1 -24 -24 v-112 a24 24 0 0 1 24 -24 z" />
      <path d="M74 100 h82 M74 142 h122" />
    </g>`,
  shield: `
    <g transform="translate(${W / 2 - 100}, ${CENTER_Y - 120})" fill="none" stroke="#ffffff" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">
      <path d="M100 20 l88 34 v92 c0 62 -38 104 -88 128 c-50 -24 -88 -66 -88 -128 v-92 z" />
      <path d="M62 132 l28 30 l52 -62" />
    </g>`,
};

const card = ({ from, to, emblem, headline, subtitle }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${from}" />
      <stop offset="1" stop-color="${to}" />
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.44" r="0.62">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.20" />
      <stop offset="1" stop-color="#ffffff" stop-opacity="0" />
    </radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)" />
  <rect width="${W}" height="${H}" fill="url(#glow)" />
  ${lines('TURKSQUARE', 210, 40, 700, 0.72)}
  <circle cx="${W / 2}" cy="${CENTER_Y}" r="215" fill="#ffffff" fill-opacity="0.12" stroke="#ffffff" stroke-opacity="0.35" stroke-width="4" />
  ${EMBLEMS[emblem]}
  ${lines(headline, 1570, 76, 700, 1)}
  ${lines(subtitle, 1780, 40, 400, 0.82)}
</svg>`;

const CARDS = [
  {
    file: 'hosgeldin.jpg',
    from: '#6355D8', to: '#2E2668', emblem: 'monogram',
    headline: 'TurkSquare’e\nhoş geldin',
    subtitle: 'Amerika’daki Türk topluluğu\ntek uygulamada.',
  },
  {
    file: 'carsi.jpg',
    from: '#0EA5E9', to: '#0B3E6F', emblem: 'bag',
    headline: 'Çarşı’da\nne var?',
    subtitle: 'Eşya, hizmet ve iş ilanları;\nhepsi topluluğun içinden.',
  },
  {
    file: 'toplulukta-bugun.jpg',
    from: '#F59E0B', to: '#9A3412', emblem: 'speech',
    headline: 'Bugün neler\nkonuşuluyor?',
    subtitle: 'Sorunu sor, deneyimini paylaş;\naynı yoldan geçenler cevaplasın.',
  },
  {
    file: 'guvende-kal.jpg',
    from: '#10B981', to: '#064E3B', emblem: 'shield',
    headline: 'Güvende kal',
    subtitle: 'Şüpheli ilanı ve mesajı bildir.\nAcil durumda SOS bir dokunuş.',
  },
];

await mkdir(OUT, { recursive: true });
for (const spec of CARDS) {
  // SVG birimleri 72 dpi nokta sayilir; density 144 ile iki kat cizip 1080x1920
  // e indirmek, yazinin kenarlarini JPEG'e yumusak birakiyor.
  const buffer = await sharp(Buffer.from(card(spec)), { density: 144 })
    .resize(W, H)
    .jpeg({ quality: 84, progressive: true, mozjpeg: true })
    .toBuffer();
  await writeFile(resolve(OUT, spec.file), buffer);
  console.log(`${spec.file}  ${(buffer.length / 1024).toFixed(0)} KB`);
}
