-- Bir paylaşımı profilin başına sabitlemek.
--
-- Izgara bugüne kadar yalnızca tarihe göre diziliyordu: üyenin kendini en iyi
-- anlatan paylaşımı, üstüne üç tane daha yazdığı anda görünmez oluyordu.
-- Sabitleme bunu düzeltiyor ve bir tarih olarak saklanıyor, bayrak olarak
-- değil: aynı anda birden fazla sabit varsa hangisinin önce geleceğini de
-- söylemesi gerekiyor.
--
-- Yorumlara kapatma için yeni bir sütun yok: `comments_enabled` 001'den beri
-- duruyor ve yorum yazma ucu zaten ona bakıyordu. Eksik olan tek şey, üyenin
-- onu değiştirebileceği bir yoldu.
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

-- Profil ızgarası "önce sabitler, sonra yeniler" diye sıralanıyor. Kısmi
-- indeks yalnızca sabitlenmişleri tutuyor: bunlar üye başına en fazla birkaç
-- kayıt, tüm tabloyu indekslemek boşuna yer olurdu.
CREATE INDEX IF NOT EXISTS community_posts_pinned_idx
  ON community_posts(author_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;
