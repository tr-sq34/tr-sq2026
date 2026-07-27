# Passkey yayın kontrol listesi

Mobil istemci, WebAuthn imzasını yalnızca cihazın sistem kimlik sağlayıcısından alır. Challenge, origin, RP ID, imza ve sayaç doğrulamasının tamamı `auth-service` tarafından yapılır.

## Yayından önce zorunlu işlemler

1. Geçici paket kimliğini (`com.example.americaHub`) yayın paket kimliğiyle değiştirin ve iOS `Runner.entitlements` içindeki Associated Domains yeteneğini imzalama profilinde etkinleştirin.
2. `https://turksquare.com/.well-known/apple-app-site-association` adresinde, yönlendirme olmadan, gerçek Apple Team ID ile `<TEAM_ID>.<BUNDLE_ID>` `webcredentials` kaydını yayınlayın.
3. `https://turksquare.com/.well-known/assetlinks.json` adresinde, yönlendirme olmadan `application/json` ile Android paket adı ve **yayın imza sertifikasının** SHA-256 parmak izleri için aşağıdaki ilişkiyi yayınlayın:

```json
[
  {
    "relation": ["delegate_permission/common.get_login_creds"],
    "target": {
      "namespace": "android_app",
      "package_name": "<ANDROID_PACKAGE_ID>",
      "sha256_cert_fingerprints": ["<RELEASE_CERT_SHA256>"]
    }
  }
]
```

4. `WEBAUTHN_RP_ID=turksquare.com` ve `WEBAUTHN_ORIGIN=https://turksquare.com` değerlerini production ortamında kullanın; localhost veya geliştirme origin'ini production'a taşımayın.
5. Gerçek Android 9+ ve Face ID / Touch ID etkin iPhone üzerinde kayıt, giriş, iptal, alan-adı ilişkilendirme hatası ve eski/iptal edilmiş credential senaryolarını test edin.

Passkey düğmesi yalnızca `--dart-define=USE_MOCK_SERVICES=false` ile API kimlik doğrulama modu açıkken sunulur. İlişkilendirme dosyaları yayınlanmadan bu modu production'a almayın.
