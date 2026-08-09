/// Why a message is being reported.
///
/// The wire value is what the gateway stores and what the moderation queue
/// sorts on, so it must never change with the wording. The list is deliberately
/// specific instead of a single "inappropriate": Apple's App Review guideline
/// 1.2 and Google Play's user-generated content policy both expect child safety
/// and self-harm to be their own paths, and a reviewer needs to see which one a
/// user picked before opening the report.
enum ReportCategory {
  childSafety(
    'child_safety',
    'Çocuk güvenliği',
    'Reşit olmayan biriyle ilgili istismar, tehlike veya uygunsuz iletişim',
  ),
  selfHarm(
    'self_harm',
    'Kendine zarar veya intihar',
    'Kendine zarar verme, intihar tehdidi veya buna teşvik',
  ),
  violenceThreat(
    'violence_threat',
    'Şiddet veya tehdit',
    'Fiziksel zarar tehdidi, şiddet çağrısı',
  ),
  hateSpeech(
    'hate_speech',
    'Nefret söylemi',
    'Irk, din, köken, cinsiyet veya kimlik üzerinden saldırı',
  ),
  harassment(
    'harassment',
    'Taciz veya zorbalık',
    'Israrlı rahatsız etme, hakaret, aşağılama',
  ),
  sexualContent(
    'sexual_content',
    'Cinsel içerik',
    'İstenmeyen cinsel içerik veya teklif',
  ),
  scamFraud(
    'scam_fraud',
    'Dolandırıcılık',
    'Sahte ilan, ödeme tuzağı, kimlik avı',
  ),
  illegalGoods(
    'illegal_goods',
    'Yasa dışı ürün veya hizmet',
    'Uyuşturucu, silah, sahte belge ve benzeri',
  ),
  spam('spam', 'Spam', 'Tekrarlayan reklam veya istenmeyen toplu mesaj'),
  other('other', 'Diğer', 'Yukarıdakilere uymayan bir kural ihlali');

  const ReportCategory(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}
