-- Silinen hesabin Community'deki izi.
--
-- 039 iki durum tanidi: donduruldu ve silinmeyi bekliyor. Ucuncusu eksikti -
-- bekleme suresi dolup kimlik gercekten silindiginde bu tarafta hicbir sey
-- degismiyordu. Identity e-postayi ve adi sildikten sonra bile uyenin gorunen
-- adi, sehri, memleketi ve kullanici adi burada duruyordu; silme yalnizca
-- yarim yapilmis olurdu.
ALTER TABLE community_profile_projection
  DROP CONSTRAINT IF EXISTS community_profile_projection_closed_reason_check;
ALTER TABLE community_profile_projection
  ADD CONSTRAINT community_profile_projection_closed_reason_check
  CHECK (closed_reason IS NULL OR closed_reason IN ('frozen', 'deletion_pending', 'purged'));

-- Projeksiyon satiri silinmiyor, bosaltiliyor: paylasimlar, yorumlar ve baska
-- uyelerin sohbetleri author_id ile bu satira bakiyor. Satir gidince akis
-- yazarini bulamaz, kalan icerik sahipsiz kalirdi. Kalan tek sey artik bir
-- kisiyi gostermeyen bir ad.
--
-- Ad sabiti Identity'deki ile ayni (account_purge.ts, PURGED_DISPLAY_NAME):
-- olay zaten adi tasiyor, buradaki varsayilan yalnizca olayin hic gelmedigi
-- eski satirlar icin gecerli degil - hicbir satiri kendiliginden degistirmiyor.
COMMENT ON COLUMN community_profile_projection.closed_reason IS
  'frozen: uye donduruldu. deletion_pending: silme talebi var, otuz gun bekleniyor. purged: kimlik silindi, bu satirdaki ad artik bir kisiyi gostermiyor.';
