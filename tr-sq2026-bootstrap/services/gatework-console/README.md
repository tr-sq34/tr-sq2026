# TurkSquare Gatework

Gatework, TurkSquare operasyon ekibinin güvenli yönetim konsoludur. Community, Identity, Matrix veya Vault veritabanlarına doğrudan bağlanmaz; yalnızca domain API'lerini kullanır.

## Local development

1. `.env.example` dosyasını `.env.local` olarak kopyalayın ve yalnızca yerel test değerleri girin.
2. `npm ci && npm run dev`
3. Production'da Cloudflare Access, MFA ve Tunnel zorunludur. Uygulamanın yalnız başına internete açılması desteklenmez.

`GATEWORK_SESSION_SECRET` ve ilk owner e-postası AWS Secrets Manager dışında tutulmaz.
