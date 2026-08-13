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
| Mesajlar | canlı | Messaging gateway |
| Sistem ve Denetim | canlı | Kimlik + Community + Messaging gateway (yalnızca okuma) |
| Çarşı, Güvenlik, Analitik, Doğrulama | bağlanmadı | — |

Bağlanmamış bölümler sahte veri göstermez; ilgili API ve audit sözleşmesi
etkinleşene kadar açıkça "bağlanmadı" der.
