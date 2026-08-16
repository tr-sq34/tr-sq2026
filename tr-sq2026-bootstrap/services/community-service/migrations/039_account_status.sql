-- Kapali hesabin izi.
--
-- Uye hesabini dondurdugunde ya da silmeyi istediginde Identity oturumlarini
-- kesiyor, ama Community bunu bilmiyordu: paylasimlar akista, profil aranabilir
-- halde duruyordu. "Hesabimi kapattim" diyen birine gore bu, kapanmamis
-- demektir.
--
-- Tek bir zaman damgasi tutuluyor, "aktif mi" bayragi degil: ne zaman
-- kapandigini bilmek, otuz gunluk silme suresini burada da hesaplayabilmek
-- demek. Durumun kendisi ayri bir sutunda cunku dondurma ile silme talebi ayni
-- sey degil - biri geri donmeyi bekliyor, digeri veriyi bekliyor.
ALTER TABLE community_profile_projection
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
ALTER TABLE community_profile_projection
  ADD COLUMN IF NOT EXISTS closed_reason TEXT
  CHECK (closed_reason IS NULL OR closed_reason IN ('frozen', 'deletion_pending'));

-- Akis her sayfada yazarin acik olup olmadigini soruyor; bu sorunun tam tarama
-- olmamasi icin.
CREATE INDEX IF NOT EXISTS community_profile_projection_closed_idx
  ON community_profile_projection(user_id)
  WHERE closed_at IS NOT NULL;
