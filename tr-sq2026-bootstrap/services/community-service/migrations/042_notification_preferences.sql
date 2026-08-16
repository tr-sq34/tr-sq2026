-- Bildirim tercihleri.
--
-- Menudeki "Bildirim Tercihleri" satiri da hicbir yere gitmiyordu ve altinda
-- "Anlik bildirim & e-posta" yaziyordu - ikisi de gonderilmiyor. Bu tablo o
-- satirin arkasi: zilde ne gorunecegini uye seciyor.
--
-- Satir yoksa acik. Yeni bir uyeye kayit sirasinda alti satir yazmak, hicbir
-- sey secmemis birinin secim yapmis gibi gorunmesi demek; ayrica ileride yeni
-- bir tur eklendiginde herkes icin kapali baslardi.
--
-- Listede olmayan iki tur bilerek yok:
--   support_answer -> uyenin kendi sordugu sorunun cevabi. Sormus birinin
--                     cevabi kacirmasini "tercih" diye kaydetmek dogru degil.
--   announcement   -> hesabi ilgilendiren duyurular buradan gidiyor. Panelde
--                     "kac uyeye ulasti" diye bir sayi var ve o sayinin
--                     dogru kalmasi, duyurunun kapatilamamasina bagli.
-- Ekranda da bunlar kapatilamaz olarak, sebebiyle birlikte yaziyor.
--
-- Tercih okuma aninda uygulaniyor, yazma aninda degil: kapali bir turu tekrar
-- acan uye o sirada birikmis olani goruyor. Yazarken elemek, kapali gecen
-- surede olan biteni geri donulmez bicimde silmek olurdu.
CREATE TABLE member_notification_preferences (
  user_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN (
    'post_comment',
    'post_like',
    'listing_save',
    'listing_like',
    'special_request',
    'friend_request'
  )),
  enabled BOOLEAN NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, kind)
);

-- Zil sorgusu her acilista bu tabloya bakiyor; uye basina en fazla alti satir
-- var, o yuzden birincil anahtar disinda bir indekse gerek yok.
