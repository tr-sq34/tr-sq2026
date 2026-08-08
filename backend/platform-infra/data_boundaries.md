# Production data boundaries

Bu platform tek bir veritabanı veya ortak servis hesabı kullanmaz.

| Sınır | Depolama | İçerik | Erişim kuralı |
|---|---|---|---|
| Identity | Ayrı PostgreSQL kümesi (`IDENTITY_DATABASE`) | kullanıcı hesabı, parola hash’i, oturumlar, passkey public key’leri | yalnızca auth-service |
| Community | Ayrı Postgres/PostGIS kümesi (`COMMUNITY_DATABASE`) | Akış, yaklaşık konum hücresi, etkileşim, anket | community-service; yalnızca kullanıcı UUID’si |
| Verification vault | Ayrı PostgreSQL kümesi (`DOCUMENT_VAULT_DATABASE`) | evrak meta verisi, KMS referansı, denetim izi | vault-service ve yetkili reviewer rolü |
| Media object store | Ayrı özel S3/R2 bucket’ları | fotoğraf/video/evrak ikili dosyaları | kısa ömürlü tek amaçlı upload/download imzaları |
| Analytics | Kimliksiz olay ambarı | toplulaştırılmış ürün metrikleri | ham PII, evrak ve tam koordinat yasak |

## Zorunlu korumalar

- Her hizmet için farklı ağ segmenti, ayrı database kullanıcısı ve en az yetki; çapraz veritabanı erişimi yasaktır.
- Evrak bucket’ı medya bucket’ından ayrı, private ve KMS envelope encryption ile şifreli olur. Evrak byte’ları PostgreSQL’e yazılmaz.
- Yükleme akışında MIME/boyut doğrulaması, zararlı yazılım taraması, EXIF/GPS temizliği ve içerik hash’i doğrulaması tamamlanmadan içerik görünür olmaz.
- Community konumu tam koordinat olarak karta dönmez. Yakınlık sorgusu PostGIS’te yürür; API yalnızca yaklaşık etiket döndürür.
- Her servis audit için `request_id` üretir; loglarda token, presigned URL, evrak içeriği veya tam koordinat bulunmaz.
- Yedekler her sınırda ayrı şifreleme anahtarıyla şifrelenir; geri yükleme ve silme işlemleri düzenli test edilir.

Bu repodaki migration dosyaları ayrı veritabanlarına uygulanmalıdır; aynı PostgreSQL instance içindeki farklı schema’lar üretim için bu izolasyonun yerine geçmez.
