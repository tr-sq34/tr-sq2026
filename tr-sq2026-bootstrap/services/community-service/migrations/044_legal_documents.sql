-- Kullanim Kosullari ve Gizlilik Politikasi.
--
-- Giris ekraninin altinda "Devam ederek Kullanim Kosullari ve Gizlilik
-- Politikasi'ni kabul etmis olursunuz" yaziyor ve iki baglanti da altiniz
-- ciziliydi. Ikisi de hicbir yere gitmiyordu: uygulamada, panelde, depoda
-- boyle bir metin hic olmadi. Uyeden okuyamadigi bir seyi kabul etmesi
-- isteniyordu.
--
-- Metin koda gomulmuyor. Bir gizlilik politikasi hukuki bir taahhut ve her
-- degistiginde uygulamanin yeni surumunu magazadan gecirmek, metnin gunu
-- gecmis kalmasinin en yaygin sebebi. Panelden yazilip panelden yayimlaniyor.
--
-- Surumler siliniyor degil, ustune yeni surum yaziliyor: "o tarihte hangi
-- metni kabul ettim" sorusunun cevabi bir yerde durmali. Yayimlanmis bir surum
-- artik degistirilemez; degisiklik yeni bir surum acar.
CREATE TABLE legal_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Iki metin var ve ikisi ayri sayiliyor. Ortak bir surum numarasi, yalnizca
  -- gizlilik metni degistiginde kosullarin da degismis gorunmesi demekti.
  kind TEXT NOT NULL CHECK (kind IN ('terms', 'privacy')),
  version INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  -- Neyin degistigi. Uyeye de gosterilebilir olsun diye ayri duruyor: "metin
  -- guncellendi" demek, hicbir sey dememekle ayni sey.
  change_note TEXT,
  -- NULL ise taslak. Uygulama yalnizca yayimlanmis olani okuyor, cunku yarim
  -- birakilmis bir cumlenin uyeye hukuki metin diye gitmesi geri alinamaz.
  published_at TIMESTAMPTZ,
  published_by UUID,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (kind, version)
);

-- Her tur icin tek bir taslak. Iki taslak, "hangisi yayimlanacak" sorusunu
-- panelin cevaplayamayacagi bir soru haline getirirdi.
CREATE UNIQUE INDEX legal_documents_single_draft
  ON legal_documents (kind) WHERE published_at IS NULL;

-- Uygulamanin sordugu tek soru: bu turun en son yayimlanmis metni.
CREATE INDEX legal_documents_published
  ON legal_documents (kind, version DESC) WHERE published_at IS NOT NULL;

-- Iki taslak, bos bir editorle baslamamak icin.
--
-- Bunlar yayimlanmiyor. Yayimlamak bir insanin karari ve panelde, hic
-- yayimlanmamis bir metnin uzerinde bunu soyleyen bir uyari duruyor. Metinler
-- sistemin gercekte ne yaptigini anlatiyor - hangi veriyi tuttugunu, nerede
-- tuttugunu, ne kadar sure sakladigini - cunku dogru olmayan bir gizlilik
-- politikasi, olmayan bir gizlilik politikasindan daha kotudur.
INSERT INTO legal_documents (kind, version, title, body, change_note) VALUES
('privacy', 1, 'Gizlilik Politikasi',
'Bu metin TurkSquare uygulamasinin hangi bilgileri topladigini, nicin
topladigini ve ne kadar sure sakladigini anlatir.

## Topladigimiz bilgiler

**Hesabini acarken:** ad soyad, e-posta adresi ve parolan. Parola sunucuda
duz metin olarak tutulmaz; yalnizca geri cevrilemeyen bir ozeti saklanir.

**Kurulum adimlarinda:** yasadigin sehir ve eyalet, Amerika''ya gelis ayin ve
yilin, geldigin ulke ve sehir, ilgi alanlarin ve uygulamayi kullanma amacin.
Bunlar seni yakinindaki uyelerle ve isine yarayacak iceriklerle bulusturmak
icin kullanilir.

**Kullanirken:** paylasimlarin, yorumlarin, hikayelerin, carsi ilanlarin,
forum konularin, begenilerin ve takip ettigin kisiler. Ozel mesajlarin
sunucuda saklanir ve yalnizca sohbetin taraflarina ve bir sikayet uzerine
inceleyen moderasyon ekibine acilir.

**Kimlik dogrulama sirasinda:** dogrulama icin yukledigin belgeler ayri ve
sifreli bir alanda tutulur. Bu belgeler profilinde gorunmez, baska uyelere
gosterilmez ve dogrulama sonuclandiktan sonra saklama suresi dolunca silinir.

**Yardim Cagrisi kullanirsan:** o an bulundugun konum. Konum yalnizca cagriyi
gonderdiginde alinir; uygulama arka planda seni izlemez.

**Teknik kayitlar:** giris yaptigin cihaz ve oturum bilgisi, uygulamanin
cokme kayitlari ve hata gunlukleri.

## Bilgilerin nerede duruyor

Veriler Microsoft Azure''un Amerika Birlesik Devletleri bolgesindeki
sunucularinda tutulur. Baglantilar Cloudflare uzerinden gecer. E-posta
gonderimi bir e-posta saglayicisi araciligiyla yapilir.

Parolani belirlerken parolanin bilinen bir sizintida gecip gecmedigini
kontrol ederiz. Bu kontrol parolanin kendisi gonderilmeden, yalnizca ozetinin
ilk bes karakteri gonderilerek yapilir.

## Ne kadar sure saklaniyor

Hesabin acik oldugu surece. Hesabini sildirmek istedigini bildirdiginde
verilerin silinme sirasina alinir; vazgecme suresi icinde tekrar giris
yaparsan talep geri alinir. Sure dolduktan sonra paylasimlarin, mesajlarin,
rozetlerin ve profilin silinir.

Hesabini dondurdugunda verilerin silinmez; profilin baskalarina gorunmez
olur ve oturumlarin kapatilir.

## Haklarin

Bilgilerine erisme, yanlis olanlari duzeltme, hesabini dondurma ve silinmesini
isteme hakkin var. Bunlarin hepsi uygulamadaki Hesap Ayarlari ekranindan
yapilabilir.

## Bize ulasmak

Gizlilikle ilgili sorularini uygulamadaki Yardim ve Destek ekranindan
iletebilirsin.',
'Ilk taslak. Yayimlanmadan once hukuki inceleme gerekiyor.'),

('terms', 1, 'Kullanim Kosullari',
'TurkSquare, Amerika''da yasayan Turk toplulugu icin kurulmus bir uygulamadir.
Uygulamayi kullanarak asagidaki kosullari kabul etmis olursun.

## Hesabin

Hesabini acarken verdigin bilgilerin dogru olmasi gerekir. Hesabin sana
aittir; baskasina devredemez, baskasi adina hesap acamazsin. Parolanin
guvenligi senin sorumlulugunda.

On sekiz yasindan kucuksen uygulamayi kullanamazsin.

## Paylastiklarin

Paylastigin her sey senin sorumlulugunda. Su icerikler yasak:

- Baskasina yonelik hakaret, tehdit, taciz ve nefret soylemi
- Yaniltici bilgi, dolandiricilik ve sahte ilan
- Baskasinin izni olmadan paylasilan ozel bilgi veya gorsel
- Telif hakki sana ait olmayan icerik
- Yasa disi urun ve hizmet satisi

Bu kurallari cigneyen icerik kaldirilir. Tekrarlanmasi halinde hesap suresiz
olarak kapatilabilir. Kararlarin gerekcesi sana bildirilir.

Paylastiklarinin mulkiyeti sende kalir. Uygulamanin bu icerigi uygulama
icinde gosterebilmesi icin gereken izni vermis olursun; bu izin icerigi
sildiginde sona erer.

## Carsi

Carsi bir ilan tahtasidir. Alici ile satici arasindaki anlasmaya, odemeye ve
teslimata TurkSquare taraf degildir; bu islemlerden dogan anlasmazliklardan
sorumlu tutulamaz. Tanimadigin biriyle alisveris yaparken dikkatli ol.

## Yardim Cagrisi

Yardim Cagrisi bir acil durum hizmeti degildir. Hayati tehlike varsa once
911''i ara. Uygulamadaki cagri, topluluk gonullulerine ve destek ekibine
ulasir; belirli bir surede yanit verilecegi garanti edilmez.

## Dogrulama

Dogrulanmis rozet, belgelerin incelendigini gosterir. Rozet bir tavsiye veya
kefalet degildir.

## Hizmetin surekliligi

Uygulama oldugu gibi sunulur. Bakim, ariza ve gelistirme sebebiyle hizmet
gecici olarak kesilebilir.

## Degisiklikler

Bu kosullar degistiginde yeni surum uygulamada yayimlanir ve degisikligin ne
oldugu belirtilir.

## Iletisim

Sorularini uygulamadaki Yardim ve Destek ekranindan iletebilirsin.',
'Ilk taslak. Yayimlanmadan once hukuki inceleme gerekiyor.');
