/// Ülke kodundan bayrak.
///
/// Bayraklar bir simge dosyası olarak taşınmıyor: Unicode'un bölge göstergesi
/// harfleri iki harflik kodun kendisinden türetiliyor, yani yeni bir ülke
/// eklendiğinde uygulamaya hiçbir şey eklemek gerekmiyor. Tanımadığı bir kod
/// için boş dönüyor - "TR" yerine soru işaretli bir kutu çizmek, bilinmeyen bir
/// ülkeyi bozuk bir ülke gibi göstermek olurdu.
String? countryFlag(String? code) {
  final value = (code ?? '').trim().toUpperCase();
  if (value.length != 2) return null;
  final first = value.codeUnitAt(0);
  final second = value.codeUnitAt(1);
  const a = 65; // 'A'
  const z = 90; // 'Z'
  if (first < a || first > z || second < a || second > z) return null;
  const base = 0x1F1E6; // 🇦
  return String.fromCharCodes([base + (first - a), base + (second - a)]);
}
