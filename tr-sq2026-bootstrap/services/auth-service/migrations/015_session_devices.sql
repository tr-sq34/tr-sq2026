-- Oturumun kimden geldigi.
--
-- Yenileme jetonu ailesi bir oturum demek: bir cihazda bir kez giris yapiliyor,
-- sonrasinda jeton kendini yeniliyor. Ama satirda cihaza dair hicbir sey yoktu,
-- bu yuzden ne uye ne de panel "hesabima nereden girilmis" sorusuna
-- bakabiliyordu. Elde yalnizca "su kadar acik oturum var" vardi ve bu, calinmis
-- bir oturumu fark etmeye yetmez.
ALTER TABLE refresh_token_families
  ADD COLUMN IF NOT EXISTS user_agent TEXT,
  -- Tam IP degil, blogu. "Ayni yerden mi geliyor" sorusuna /24 (IPv6'da /48)
  -- cevap veriyor; adresin tamami ise uyenin nerede oldugunun gunluk kaydi
  -- olurdu. Panelin isi supheli olani gormek, uyeyi takip etmek degil.
  ADD COLUMN IF NOT EXISTS ip_prefix TEXT,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

-- Var olan satirlar icin son gorulme bilinmiyor. Kurulus anini yazmak, aylardir
-- dokunulmamis bir oturumu bugun kullanilmis gibi gostermezdi ama en azindan
-- bilinen tek gercek zaman o; NULL kalirsa liste sirasiz gorunurdu.
UPDATE refresh_token_families SET last_seen_at=created_at WHERE last_seen_at IS NULL;

-- Liste her zaman "bu uyenin acik oturumlari, en son gorulen ustte" sorgusu.
CREATE INDEX IF NOT EXISTS refresh_token_families_user_seen_idx
  ON refresh_token_families(user_id, last_seen_at DESC)
  WHERE revoked_at IS NULL;
