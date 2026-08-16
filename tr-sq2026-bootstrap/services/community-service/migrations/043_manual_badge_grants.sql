-- Elle verilen rozetin kim tarafindan verildigi.
--
-- Migration 016 rozet katalogunu veri olarak kurdu ve `manual_only` sutununu
-- "bunu bir yonetici verir" diye acikladi. Motor tarafinda da karsiligi vardi:
-- awardBadge(..., { allowManual: true }). O bayrak bugune kadar hicbir yerden
-- gecilmedi - yani katalogda "acil bir durumda toplulugu organize ettin" yazan
-- Dayanisma Madalyasi'ni verecek bir yol hic olmadi.
--
-- Panelden verilebilmesi icin eksik olan tek sey, verilen rozetin elle mi
-- verildigi bilgisiydi. member_badges satirinda bu yazmazsa bir denetci
-- "bu uye bu rozeti nasil aldi" sorusunu cevaplayamaz: motorun verdigi rozetle
-- operatorun verdigi rozet ayni goruntude durur.
--
-- Bos birakilan sutun "motor verdi" demek. Gecmis satirlarin hepsi oyle, cunku
-- bugune kadar elle verilebilen bir rozet olmadi; geriye donuk doldurulacak
-- bir sey yok.
ALTER TABLE member_badges
  ADD COLUMN IF NOT EXISTS granted_by UUID,
  ADD COLUMN IF NOT EXISTS granted_reason TEXT
    CHECK (granted_reason IS NULL OR char_length(granted_reason) BETWEEN 3 AND 240);

-- Panelin "bu rozet elle kac kere verildi" sorusu, kataloglu ekranda her rozet
-- icin bir kez soruluyor. Kismi indeks: satirlarin ezici cogunlugu motor
-- kaynakli ve orada bos duruyor.
CREATE INDEX IF NOT EXISTS member_badges_granted_by_idx
  ON member_badges (badge_code) WHERE granted_by IS NOT NULL;

-- --- Zil ----------------------------------------------------------------
--
-- Sessizce verilen rozet, verilmemis rozetle ayni sey. Uye Yolculuk ekranini
-- kendiliginden acmadikca madalyanin geldigini ogrenemez; operatorun yaptigi is
-- hicbir yerde gorunmez.
--
-- member_notifications.subject_id UUID, rozet kodu ise metin. Her verilise ayri
-- bir kimlik veriliyor: ayni rozet iki kere verilemedigi icin bu kimlik zaten
-- (uye, rozet) ciftinin kendisi, sadece zilin bekledigi tipte.
ALTER TABLE member_badges
  ADD COLUMN IF NOT EXISTS id UUID NOT NULL DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS member_badges_id_idx ON member_badges (id);

-- 'badge_earned' bilerek kapatilabilir turler arasinda degil (bkz. 042). Duyuru
-- ve destek yanitiyla ayni gerekce: uyenin kendisi hakkinda, elle verilmis,
-- omur boyu bir avuc tane. Kapatilacak bir gurultu yok.
ALTER TABLE member_notifications DROP CONSTRAINT IF EXISTS member_notifications_kind_check;
ALTER TABLE member_notifications ADD CONSTRAINT member_notifications_kind_check
  CHECK (kind IN ('post_comment', 'post_like', 'listing_save', 'listing_like', 'special_request',
                  'friend_request', 'announcement', 'support_answer', 'badge_earned'));
