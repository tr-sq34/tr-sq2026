# Kimlik Doğrulama Backlog'u

## Planlanan: E-posta doğrulamasını OTP koduna taşıma

- Mevcut bağlantı tabanlı e-posta doğrulamasının yerine altı haneli, tek
  kullanımlık doğrulama kodu ekranı ekle.
- Kayıt sonrasında kullanıcıyı kod giriş ekranına yönlendir; e-posta adresini
  maskeli göster ve süre sayacı ile yeniden gönderme aksiyonu sun.
- Kodları veritabanında düz metin saklama: HMAC/SHA-256 hash, 59 saniyelik TTL,
  tek kullanımlık tüketim, deneme ve yeniden gönderim rate-limitleri uygula.
- Başarılı doğrulamada hesabın `email_verified_at` alanını güncelle; güvenli
  şekilde giriş ekranına veya yeni oturuma yönlendir.
- Kullanıcının e-posta adresini değiştirebilmesi, hatalı kod mesajı, süresi
  dolmuş kod ve yeniden gönderim bekleme durumu için mobil arayüz ekle.
- Eski bağlantı doğrulamasını kademeli olarak kapatmadan önce mevcut action
  tokenlarını geçiş dönemi boyunca geçerli tut; e-posta teslimat şablonlarını
  OTP formatına geçir.
