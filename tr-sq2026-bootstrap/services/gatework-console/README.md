# TurkSquare Gatework

Gatework, TurkSquare operasyon ekibinin güvenli yönetim konsoludur. Community, Identity, Matrix veya Vault veritabanlarına doğrudan bağlanmaz; yalnızca domain API'lerini kullanır.

## Local development

1. `.env.example` dosyasını `.env.local` olarak kopyalayın ve yalnızca yerel test değerleri girin.
2. `npm ci && npm run dev`
3. Production'da Cloudflare Access, MFA ve Tunnel zorunludur. Uygulamanın yalnız başına internete açılması desteklenmez.

`GATEWORK_SESSION_SECRET` AWS Secrets Manager dışında tutulmaz.

## İlk owner hesabı

Konsol hesap açamaz; ilk owner hesabı Identity servisinin tek seferlik bootstrap
adımıyla oluşturulur. Parolanın kendisi hiçbir zaman ortam değişkenine, koda veya
depoya girmez - yalnızca argon2id özeti secret store'a konur. Adımlar:
`infra/bootstrap/gatework-identity-bootstrap.md`.

## Bölümler

| Bölüm | Durum | Bağlı servis |
| --- | --- | --- |
| İçerik Stüdyosu, Haber Merkezi, Tanıtımlar | canlı | Community |
| Üyeler | canlı | Identity (hesap, rol, oturum) + Community (davranış, kısıtlama) |
| Moderasyon | canlı | Messaging gateway + Community |
| Forum | canlı | Community |
| Çarşı ve İhaleler | canlı | Community (ilan/ihale okuma, yayından kaldırma, ihale iptali) |
| Mesajlar | canlı | Messaging gateway |
| Sistem ve Denetim | canlı | Kimlik + Community + Messaging gateway (yalnızca okuma) |
| Doğrulama | canlı | Verification vault (yalnızca okuma; belge içeriği yok) |
| Analitik ve Konum | canlı | Kimlik (hesap büyümesi) + Community (içerik ve toplulaştırılmış konum) |
| Güvenlik ve SOS | bağlanmadı | — |

Bağlanmamış bölümler sahte veri göstermez; ilgili API ve audit sözleşmesi
etkinleşene kadar açıkça "bağlanmadı" der.

## Konum verisi

Analitik ve Konum ekranı üyenin canlı konumunu, konum iznini veya hareket
geçmişini okumaz; yalnızca profilde kendi seçtiği şehir/eyalet tercihini
toplulaştırır. Beşten az üyeli şehir ve eyaletler tek tek listelenmez, tek bir
"eşik altı" satırında toplanır - küçük bir kova ile Üyeler ekranındaki şehir
filtresi yan yana getirildiğinde tek bir kişiyi işaret edebilir. Eşik ve eşik
altında kalan toplam ekranda açıkça yazılır.
