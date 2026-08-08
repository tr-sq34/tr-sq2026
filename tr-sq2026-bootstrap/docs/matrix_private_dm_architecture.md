# TurkSquare Matrix: yalnızca birebir özel mesajlaşma

## Ürün sınırı

Matrix, TurkSquare'de bir topluluk, kanal veya sunucu ürünü değildir. Mobil
uygulama Matrix markasını, oda listelerini, oda aramasını veya oda oluşturma
işlemlerini göstermez. Yalnızca WhatsApp tarzı birebir konuşmalar gösterilir.

İlk kapsam iki akıştır:

1. Bir kullanıcının başka bir kullanıcının profilinden **Mesaj gönder**
   eylemi.
2. İhale kapandığında uygun satıcı ile kazanan arasında otomatik konuşma.

Grup konuşması, herkese açık oda, federasyon, sesli oda ve Matrix kullanıcı
dizini bu fazın kapsamı dışındadır.

## Güvenlik modeli

- Synapse, Community AWS hesabında ayrı PostgreSQL kümesi ve ayrı KMS anahtarı
  ile çalışır.
- Synapse yalnızca `/_matrix/client` için private ALB üzerinden erişilir.
  `/_matrix/federation`, port 8448 ve federation listener dağıtıma dahil
  edilmez. VPC'nin internete genel çıkışı yoktur; gerekli AWS servisleri VPC
  endpoint'leriyle kullanılır.
- `enable_registration: false` olur. `registration_shared_secret` tanımlanmaz;
  Matrix kullanıcısını sadece TurkSquare messaging gateway'deki uygulama
  hizmeti (application service) oluşturabilir.
- Mobil istemci TurkSquare parolasını Matrix'e hiç göndermez. Identity OIDC
  oturumu gateway'de doğrulanır; Matrix için kısa ömürlü, cihaza bağlı erişim
  sözleşmesi sonraki mesajlaşma paketinde uygulanır.
- Oda eşlemesi, canonical sıralanmış iki TurkSquare kullanıcı kimliğiyle
  (`lower(user_a_id), higher(user_b_id)`) benzersiz tutulur. Böylece aynı iki
  kullanıcı için eşzamanlı iki DM odası oluşmaz.
- Uygulama yalnızca gateway'in verdiği konuşmaları listeler. Synapse'in genel
  oda dizini ve kullanıcı araması mobil API'den çağrılmaz.
- Oda oluşturma, mesaj gönderme, engelleme, raporlama ve ihale sonrası otomatik
  eşleştirme audit olayına yazılır. Mesaj gövdesi audit kaydına yazılmaz.

## Backend sözleşmesi

Mobil uygulama Synapse `createRoom` API'sini doğrudan çağırmaz. TurkSquare
mesajlaşma gateway'i aşağıdaki yüzeyi sağlar:

| Uç | Yetki | Davranış |
| --- | --- | --- |
| `POST /v1/messages/direct-conversations` | oturum sahibi | Hedef kullanıcı için mevcut veya yeni 1:1 DM döndürür. |
| `GET /v1/messages/conversations` | oturum sahibi | Sadece çağıranın taraf olduğu DM'leri cursor ile döndürür. |
| `GET /v1/messages/conversations/{id}/messages` | oda üyesi | Mesajları cursor ile döndürür. |
| `POST /v1/messages/conversations/{id}/messages` | oda üyesi | Metin/medya referanslı mesajı gönderir. |
| `POST /internal/messages/auction-conversations` | yalnızca Çarşı servisi | İhale satıcısı ve kazananı için idempotent DM açar. |

Gateway'in Synapse'e yaptığı oda açma isteği her zaman aşağıdaki politikayı
uygular:

```json
{
  "is_direct": true,
  "preset": "private_chat",
  "visibility": "private",
  "invite": ["@target:matrix.turksquare.com"],
  "creation_content": { "m.federate": false },
  "initial_state": [
    {
      "type": "m.room.guest_access",
      "state_key": "",
      "content": { "guest_access": "forbidden" }
    }
  ]
}
```

Bu istek bir uygulama hizmeti kimliğiyle yapılır; token yalnızca Secrets
Manager'da saklanır. `room_id` istemcinin güvenlik yetkisi için kaynak değildir:
her gateway çağrısında TurkSquare kullanıcısının oda üyeliği yeniden denetlenir.

## Dağıtım öncesi doğrulama

- İnternetten `/_matrix/federation/*` ve `:8448` erişimi bulunmamalı.
- Bir mobil kullanıcı hiçbir API ile public oda oluşturamamalı veya
  `public` görünürlükte oda açamamalı.
- Aynı iki kullanıcıya paralel DM oluşturma isteği tek oda döndürmeli.
- Üçüncü kullanıcı, konuşma kimliğini bilse dahi mesaj listesi veya gönderme
  yapamamalı.
- Engellenen kullanıcıya yeni DM ve ihale sonrası mesajlaşma açılmamalı.
- Synapse kullanıcı kaydı sadece application-service namespace'i üzerinden
  mümkün olmalı.

## Kaynaklar

- [Synapse configuration manual](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html)
- [Synapse application services](https://element-hq.github.io/synapse/latest/application_services.html)
- [Matrix room creation specification](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3createroom)
