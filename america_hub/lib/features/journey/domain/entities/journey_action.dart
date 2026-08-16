/// Bir görevin gerçekten yapıldığı yer.
///
/// Görev listesi uzun süre düz metindi: "Yaşadığın eyaleti ve şehri seç"
/// yazıyordu ama o ekranı üye kendi bulmak zorundaydı. Buradaki eşleme, göreve
/// dokununca kabuğun hangi ekranı açacağını söylüyor.
enum JourneyDestination {
  /// Yaşanan şehir/eyalet seçimi.
  location,

  /// Profil sekmesi: fotoğraf ve biyografi orada düzenleniyor.
  profileEdit,

  /// Yeni gönderi düzenleyicisi.
  composer,

  /// Akış sekmesi.
  feed,

  /// Forum.
  forum,

  /// Mesaj kutusu.
  messages,

  /// Story düzenleyicisi.
  storyComposer,
}

/// Görev kodundan ekrana. Kod tanınmıyorsa `null`: satır dokunulabilir
/// görünmüyor. Uydurma bir hedefe götürmek, hiçbir yere götürmemekten kötü —
/// üye yanlış ekranda görevi yapamadan geri dönüyor.
///
/// Kodlar `016_member_journey.sql` içindeki `journey_tasks` satırlarıyla
/// birebir aynı.
JourneyDestination? journeyDestinationOf(String taskCode) => switch (taskCode) {
  'map_pin' => JourneyDestination.location,
  'introduce_self' => JourneyDestination.profileEdit,
  'first_hello' => JourneyDestination.composer,
  'watchman' => JourneyDestination.feed,
  'taste_hunter' => JourneyDestination.forum,
  'find_neighbor' => JourneyDestination.messages,
  'be_the_light' => JourneyDestination.forum,
  'share_story' => JourneyDestination.storyComposer,
  'community_lead' => JourneyDestination.composer,
  'safe_street' => JourneyDestination.feed,
  // 'loyalty_chain' ve 'streak_beast' bilerek burada yok: ikisi de "gün
  // atlamadan gir" görevi. Açılacak bir ekran yok, uygulamayı açmanın kendisi
  // görevin ta kendisi.
  _ => null,
};

/// Satırın sonundaki kısa eylem etiketi. Görev metnini tekrar etmiyor, nereye
/// gidileceğini söylüyor.
String journeyActionLabel(JourneyDestination destination) => switch (destination) {
  JourneyDestination.location => 'Konumu seç',
  JourneyDestination.profileEdit => 'Profili düzenle',
  JourneyDestination.composer => 'Paylaş',
  JourneyDestination.feed => 'Akışa git',
  JourneyDestination.forum => 'Foruma git',
  JourneyDestination.messages => 'Mesajlara git',
  JourneyDestination.storyComposer => 'Story ekle',
};
