-- Kullanıcı adı ve takip.
--
-- İki eksik, tek göç.
--
-- 1) Bir üyeyi işaret etmenin tek yolu görünen adıydı. Görünen ad benzersiz
--    değil: "Ahmet Yilmaz" adında üç kişi varsa hiçbiri diğerinden ayırt
--    edilemiyor, hiçbiri anılamıyor, hiçbirinin profiline verilebilecek bir
--    adres yok. Handle bunun için var ve benzersizliği veritabanı garanti
--    etmeli - uygulamanın "bu ad boş mu" sorusu ile INSERT arasındaki boşlukta
--    aynı adı iki kişi alabilir.
--
--    Handle Community'ye ait, identity'ye değil. Görünen ad, şehir ve
--    onboarding cevapları identity'nin projeksiyonu; handle ise üyenin bu
--    uygulamada kendine seçtiği ad ve yalnızca burada yazılıyor. member_profiles
--    tam olarak bunun tablosu.
--
-- 2) relationship_projection 002'den beri 'following' değerini CHECK'inde
--    taşıyor ama hiçbir satır yazılmadı; 029 yalnızca 'friend' yazıyor.
--    "Takipçi" ve "Takip edilen" sayıları bu yüzden hiç var olmadı, profilde
--    yalnızca simetrik arkadaşlık sayacı vardı. Tek yönlü takip ayrı bir rıza:
--    takip etmek için karşı tarafın onayı gerekmiyor, arkadaşlık için gerekiyor.
--    Bu göç yeni bir tablo açmıyor, var olan satır tipini kullanıma sokuyor.

ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS username TEXT;

-- Küçük harf, rakam, alt çizgi ve nokta. Büyük harfe izin verilseydi "Ahmet" ve
-- "ahmet" iki ayrı satır olurdu ve aşağıdaki benzersizlik indeksi ikisini aynı
-- ada indirgeyip birini reddederdi: kural iki yerde iki farklı şey söylerdi.
-- Nokta ile başlamak/bitmek ve arka arkaya iki nokta yok; "ali..veli" ile
-- "ali.veli" gözle ayırt edilemeyecek kadar birbirine benziyor.
ALTER TABLE member_profiles
  DROP CONSTRAINT IF EXISTS member_profiles_username_check;
ALTER TABLE member_profiles
  ADD CONSTRAINT member_profiles_username_check
  CHECK (
    username IS NULL
    OR (username ~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$' AND username !~ '\.\.')
  );

-- Benzersizlik burada bitiyor. Uygulamadaki "bu ad müsait mi" denetimi yalnızca
-- kullanıcıya erken cevap vermek için; son sözü bu indeks söylüyor.
CREATE UNIQUE INDEX IF NOT EXISTS member_profiles_username_key
  ON member_profiles(username) WHERE username IS NOT NULL;

-- Takipçi sayısı ve takipçi listesi subject_id üzerinden okunuyor. 002'deki tek
-- indeks (viewer_id, subject_id) sırasıyla; "beni kim takip ediyor" sorusu o
-- indeksten faydalanamıyor ve tabloyu baştan sona tarıyordu.
CREATE INDEX IF NOT EXISTS relationship_projection_subject_idx
  ON relationship_projection(subject_id) WHERE active;
