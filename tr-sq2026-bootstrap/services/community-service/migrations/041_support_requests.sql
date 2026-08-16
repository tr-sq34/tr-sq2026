-- Yardim ve Destek.
--
-- Menude "Yardim & Destek" satiri vardi ve dokununca hicbir sey olmuyordu.
-- Uygulamada bir sey ters gittiginde uyenin yazacagi tek yer yoktu: ne bir
-- adres, ne bir form. Sikayet ("report") baska bir sey - o, baska bir uyeyi
-- isaret ediyor. Bu tablo, uyenin platformun kendisiyle konustugu yer.
--
-- Iki tablo, cunku destek tek bir mesaj degil. Uye yaziyor, operator cevap
-- veriyor, uye "hala olmuyor" diyor. Tek satirda tutulsaydi ikinci cevap
-- birincisinin ustune yazilirdi ve kimin ne zaman ne dedigi kaybolurdu.
--
-- status uc degerden ibaret ve hangisinin sirada oldugu buradan okunuyor:
--   open     -> son soz uyede, operator bekliyor
--   answered -> son soz operatorde, uye bekliyor
--   closed   -> kapandi; uye yeniden yazarsa yeni talep acilir
--
-- Kapatma silmiyor. Bir uye "neden hesabim donduruldu" diye sorduysa, o soru ve
-- verilen cevap ikisinin de elinde kalmali; kapanan sey konusma degil, siradan
-- dusme.
CREATE TABLE support_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL,
  -- Konu basligi, kuyrugu bolmek icin. Serbest metin degil: operator "hangi
  -- talepler odemeyle ilgili" diye sorabilmeli.
  topic TEXT NOT NULL CHECK (topic IN ('account', 'safety', 'marketplace', 'content', 'technical', 'other')),
  subject TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'answered', 'closed')),
  -- Uygulamanin surumu ve platformu. Uyeye "hangi surumu kullaniyorsun" diye
  -- sormak, cevabi zaten elimizde olan bir soru. Bos olabilir: web'den ya da
  -- eski bir surumden gelen talepte bu bilgi yok ve uydurulmuyor.
  app_version TEXT,
  platform TEXT CHECK (platform IS NULL OR platform IN ('android', 'ios', 'web')),
  -- Ayni formun iki kez gonderilmesi iki talep degil. Uygulama her form icin
  -- bir anahtar uretiyor; ikinci gonderim ayni talebi geri aliyor.
  client_token UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Kuyrugun sirasi bu iki alandan cikiyor: en uzun suredir cevap bekleyen
  -- talep basta. created_at ile siralamak, uc kez yazip cevap alamayan uyeyi
  -- ilk gun yazip cevaplanmis olanin arkasinda birakirdi.
  last_member_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_staff_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  closed_by UUID,
  closure_reason TEXT,
  UNIQUE (member_id, client_token)
);

CREATE TABLE support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES support_requests(id) ON DELETE CASCADE,
  author_kind TEXT NOT NULL CHECK (author_kind IN ('member', 'staff')),
  author_id UUID NOT NULL,
  -- Operatorun o an tasidigi roller. Rol daha sonra geri alinsa bile cevabin
  -- hangi yetkiyle verildigi okunabilir kalmali.
  author_roles TEXT[],
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Kuyruk: once cevap bekleyenler, icinde en cok bekleyen basta.
CREATE INDEX support_requests_queue_idx ON support_requests(status, last_member_at);
CREATE INDEX support_requests_member_idx ON support_requests(member_id, updated_at DESC);
CREATE INDEX support_messages_request_idx ON support_messages(request_id, created_at);

-- Talebi cevaplandiginda uyeye zil calmali. Cevabi gormek icin uyenin destek
-- ekranini kendiliginden acmasini beklemek, cevabi gondermemekle ayni sey.
ALTER TABLE member_notifications DROP CONSTRAINT IF EXISTS member_notifications_kind_check;
ALTER TABLE member_notifications ADD CONSTRAINT member_notifications_kind_check
  CHECK (kind IN ('post_comment', 'post_like', 'listing_save', 'listing_like', 'special_request', 'friend_request', 'announcement', 'support_answer'));
