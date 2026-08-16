-- Bekleme suresi dolan hesabin kalici temizligi.
--
-- 013 iki sutun ve bir indeks birakti, ama silmeyi yapacak sureç yoktu:
-- "hesabimi sil" diyen uyenin e-postasi, adi ve kurulum cevaplari otuz birinci
-- gunde de oldugu yerde duruyordu. Bekleme suresi bir soz; onu tutan bir is
-- olmadan sutun yalnizca bir niyet beyani.
--
-- Satir yine de silinmiyor. users(id) satirina bes tablo ON DELETE CASCADE,
-- gatework_audit_events ise ON DELETE RESTRICT ile bagli: DELETE ya baskasinin
-- denetim kaydini goturur ya da hic calismaz. Daha onemlisi
-- identity_outbox_events.aggregate_id de ayni satira CASCADE ile bagli - satiri
-- silen islem, silindigini Community ve Messaging'e haber verecek olayi da
-- beraberinde silerdi ve iki tarafta veri oldugu gibi kalirdi.
--
-- Yapilan sey kimligi geri donusu olmayacak sekilde silmek: e-posta, gorunen
-- ad, sifre ozeti, oturumlar, passkey'ler ve kurulum cevaplari gidiyor. Geriye
-- yalnizca yabanci anahtarlari ayakta tutan bos bir kabuk kaliyor.
ALTER TABLE users ADD COLUMN IF NOT EXISTS purged_at TIMESTAMPTZ;

-- 013'un indeksi temizlenmis satirlari da tasiyordu; her turda onlari okuyup
-- elemek gerekirdi. Kosula purged_at girince indekste yalnizca sirada bekleyen
-- hesaplar kaliyor ve is bitince satir indeksten kendiliginden dusuyor.
DROP INDEX IF EXISTS users_deletion_requested_idx;
CREATE INDEX IF NOT EXISTS users_deletion_requested_idx
  ON users(deletion_requested_at)
  WHERE deletion_requested_at IS NOT NULL AND purged_at IS NULL;

COMMENT ON COLUMN users.purged_at IS
  'Kimligin silindigi an. Dolu ise bu satirdaki e-posta ve ad artik bir kisiyi gostermiyor.';
