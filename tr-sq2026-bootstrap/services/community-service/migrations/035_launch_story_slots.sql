-- Acilis kartlari: Story seridinin ilk gun bos kalmamasi icin.
--
-- discover_screen.dart'taki serit, ne sponsorlu yuva ne de aginda Story olmayan
-- bir uyede hic cizilmiyor. Yeni bir uyenin ilk gun ikisi de yok, dolayisiyla
-- uygulama ekranin en ustunde bir bosluga aciliyordu. Buraya ornek kullanici
-- koymak soz konusu degil; konulan sey platformun kendi dort karti: uygulamanin
-- ne yaptigini anlatiyorlar ve hepsi gercek bir yere goturuyor.
--
-- Neden `stories` degil de `promotions`: stories tablosunun kisiti bir Story'yi
-- en fazla 24 saat yasatiyor. Buraya yazilan bir Story yarin kaybolurdu, yani
-- "serit bos kalmasin" sorununu bir gunlugune cozerdi. Gunluk Story'ler artik
-- panelden yayinlaniyor (Icerik Studyosu > Story paylasimi); kalici olmasi
-- gereken sey bu dort kart.
--
-- Gorseller depoya islenmis JPEG'ler, blobda degil: bu gecisi calistiran is
-- yalnizca veritabanina baglaniyor, depolama kimlik bilgisi yok. Servis onlari
-- /v1/public/launch altindan sunuyor, mediaObjectUrl de 'launch/' ile baslayan
-- anahtari imzalamak yerine oraya ceviriyor.
--
-- Sahibi: panelin actigi ilk resmi hesap. Henuz bir resmi hesap yoksa asagidaki
-- INSERT'ler sifir satir yazar ve gecis sessizce gecer - o durumda serit zaten
-- bos, ama tutarsiz bir sahiplik kaydi birakmiyoruz.

INSERT INTO media_assets (id, owner_id, status, kind, safe_url)
SELECT v.id, o.user_id, 'ready', 'image', v.key
FROM (VALUES
  ('a7f1c0d2-1111-4a11-9a01-6c7d5e4f0001'::uuid, 'launch/hosgeldin.jpg'),
  ('a7f1c0d2-1111-4a11-9a01-6c7d5e4f0002'::uuid, 'launch/carsi.jpg'),
  ('a7f1c0d2-1111-4a11-9a01-6c7d5e4f0003'::uuid, 'launch/toplulukta-bugun.jpg'),
  ('a7f1c0d2-1111-4a11-9a01-6c7d5e4f0004'::uuid, 'launch/guvende-kal.jpg')
) AS v(id, key)
CROSS JOIN LATERAL (
  SELECT user_id FROM community_system_accounts
   WHERE role = 'official' AND active ORDER BY created_at LIMIT 1
) o
ON CONFLICT (id) DO NOTHING;

-- Bir yil: bir tarih girmek zorunlu ve bu kartlarin bitis diye bir sebebi yok.
-- Suresi dolarsa panelden uzatilir, kendiliginden yeniden yayina girmez.
INSERT INTO promotions (
  id, owner_id, placement, title, subtitle, media_id, target_kind, target_value,
  starts_at, ends_at, status, decision_reason, decided_by, decided_at, display_order
)
SELECT v.id, o.user_id, 'story_slot', v.title, v.subtitle, v.media_id, v.target_kind, v.target_value,
       now(), now() + interval '1 year', 'approved',
       'Platformun kendi acilis karti; Story seridi bos acilmasin diye yerlestirildi.',
       o.user_id, now(), v.ord
FROM (VALUES
  (
    'b7f1c0d2-2222-4a22-9a02-6c7d5e4f0001'::uuid,
    'TurkSquare’e hoş geldin',
    'Amerika’daki Türk topluluğu tek uygulamada: akış, çarşı, forum ve haberler.',
    'a7f1c0d2-1111-4a11-9a01-6c7d5e4f0001'::uuid,
    NULL::text, NULL::text, 1::int
  ),
  (
    'b7f1c0d2-2222-4a22-9a02-6c7d5e4f0002'::uuid,
    'Çarşı’da ne var?',
    'Eşya, hizmet ve iş ilanları; hepsi topluluğun içinden.',
    'a7f1c0d2-1111-4a11-9a01-6c7d5e4f0002'::uuid,
    'listing'::text, 'marketplace'::text, 2::int
  ),
  (
    'b7f1c0d2-2222-4a22-9a02-6c7d5e4f0003'::uuid,
    'Bugün neler konuşuluyor?',
    'Sorunu sor, deneyimini paylaş; aynı yoldan geçenler cevaplasın.',
    'a7f1c0d2-1111-4a11-9a01-6c7d5e4f0003'::uuid,
    'post'::text, 'feed'::text, 3::int
  ),
  (
    'b7f1c0d2-2222-4a22-9a02-6c7d5e4f0004'::uuid,
    'Güvende kal',
    'Şüpheli ilanı ve mesajı bildir. Acil durumda SOS bir dokunuş uzağında.',
    'a7f1c0d2-1111-4a11-9a01-6c7d5e4f0004'::uuid,
    NULL::text, NULL::text, 4::int
  )
) AS v(id, title, subtitle, media_id, target_kind, target_value, ord)
CROSS JOIN LATERAL (
  SELECT user_id FROM community_system_accounts
   WHERE role = 'official' AND active ORDER BY created_at LIMIT 1
) o
-- Yalnizca gorseli gercekten yazilmis kartlar: yukaridaki INSERT resmi hesap
-- yoksa hicbir sey yazmadi, o zaman burada da bir sey yazilmamali.
WHERE EXISTS (SELECT 1 FROM media_assets m WHERE m.id = v.media_id)
ON CONFLICT (id) DO NOTHING;
