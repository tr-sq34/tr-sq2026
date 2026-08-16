-- Hesabi dondurma ve silme.
--
-- Iki ayri karar, iki ayri sutun: dondurma "bir sure yokum" demek, silme ise
-- "gitmek istiyorum" demek. Tek bir "aktif mi" bayragi ikisini ayirt edemezdi
-- ve geri donen uyeye hangisinden dondugunu soyleyemezdik.
--
-- Silme aninda satir silinmiyor. Uyenin yazdigi yorumlarin altindaki isim, bir
-- baskasinin sohbetindeki gecmis, arkadaslik kayitlari... hepsi bu satira
-- bagli. Bir aylik bekleme suresi hem vazgecme hakki hem de bu baglarin
-- duzgun temizlenmesi icin gereken zaman.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ;

-- Kalici silme isini yapacak olan sureç bu indeksten okuyacak; tam tarama ile
-- her gun butun uye tablosunu gezmek gerekmesin.
CREATE INDEX IF NOT EXISTS users_deletion_requested_idx
  ON users(deletion_requested_at)
  WHERE deletion_requested_at IS NOT NULL;

-- Outbox yeni bir olay tasiyacak: hesabin durumu degistiginde Community de
-- bilmeli, yoksa donmus bir uyenin profili akista durmaya devam ederdi.
-- Kisitlar tek tek dusurulup yeniden kuruluyor cunku CHECK'e deger eklemenin
-- baska bir yolu yok.
ALTER TABLE identity_outbox_events
  DROP CONSTRAINT IF EXISTS identity_outbox_events_aggregate_type_check;
ALTER TABLE identity_outbox_events
  ADD CONSTRAINT identity_outbox_events_aggregate_type_check
  CHECK (aggregate_type IN ('user_onboarding', 'user', 'user_account'));

ALTER TABLE identity_outbox_events
  DROP CONSTRAINT IF EXISTS identity_outbox_events_event_type_check;
ALTER TABLE identity_outbox_events
  ADD CONSTRAINT identity_outbox_events_event_type_check
  CHECK (event_type IN (
    'community.profile_upserted',
    'community.account_status_changed',
    'messaging.user_upserted'
  ));
