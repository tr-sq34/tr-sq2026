-- Haberin akista da bir paylasim olarak gorunmesi.
--
-- Haber Merkezi ile akis simdiye kadar birbirini hic gormedi: panelden haber
-- yayinlaniyor, uygulamada ayri bir sekmede duruyor ve akisi acan uye ondan
-- haberdar olmuyordu. Istenen sey haberin akista da bir kart olarak cikmasi -
-- gorseliyle, ozetiyle, ayni begeni ve yorumlariyla.
--
-- "Ayni" kelimesi buradaki tek zor kisim. Iki ayri sayac tutmak (haberde bir
-- begeni tablosu, akista bir baskasi) iki farkli dogru uretirdi: haber ekraninda
-- 12 begeni, akista 3. Bu yuzden akistaki kart kendi sayaclarini tasimiyor.
-- Satir yalnizca haberin akistaki yeri; begeni `news_reactions`, yorum
-- `news_comments` tablosunda kaliyor ve akis onlari okuyor. Tek kaynak var,
-- dolayisiyla iki ekranin ayrisma ihtimali de yok.
--
-- Yeni bir `post_kind` degeri eklenmedi. `migrate.ts` tum gocleri tek bir islem
-- icinde calistiriyor ve PostgreSQL ayni islemde ALTER TYPE ... ADD VALUE ile
-- eklenen bir degeri kullandirmiyor; ayrica bu satirin akistaki davranisi
-- siradan bir paylasimla ayni - farki tasiyan sey turu degil, bagli oldugu
-- haber.
ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS news_article_id UUID REFERENCES news_articles(id) ON DELETE CASCADE;

-- Bir haber akista en fazla bir kez durur. Panelden iki kez "akisa cikar"
-- denmesi ayni haberi akista iki kart yapmamali.
CREATE UNIQUE INDEX IF NOT EXISTS community_posts_news_article_idx
  ON community_posts (news_article_id)
  WHERE news_article_id IS NOT NULL;
