-- Forum: kategoriler, konular, yanıtlar ve beğeniler.
--
-- Akıştan ayrı tablolarda durmasının sebebi ömrü: community_posts bugünün
-- gündemi ve silinebilir, forum ise bir yıl sonra aranıp bulunacak bir arşiv.
-- Kategori panelden açılıyor, uygulamada ikon tablosu tutulmuyor: emoji de
-- başlık da satırın kendisinde.
CREATE TABLE forum_categories (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),slug TEXT NOT NULL UNIQUE CHECK(slug ~ '^[a-z0-9-]{2,48}$'),title TEXT NOT NULL CHECK(char_length(title) BETWEEN 2 AND 80),emoji TEXT NOT NULL DEFAULT '💬' CHECK(char_length(emoji) BETWEEN 1 AND 8),description TEXT NOT NULL DEFAULT '' CHECK(char_length(description)<=240),ordinal INT NOT NULL DEFAULT 0,is_active BOOLEAN NOT NULL DEFAULT true,created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX forum_categories_order_idx ON forum_categories(ordinal,title) WHERE is_active;

-- reply_count ve last_reply_at türetilebilir olduğu hâlde satırda duruyor:
-- "en çok yanıt" ve "son hareket" sıralamaları her sayfa isteğinde bütün
-- yanıtları saymak zorunda kalmasın diye. İkisi de yanıtla aynı işlemde
-- güncelleniyor.
CREATE TABLE forum_topics (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),category_id UUID NOT NULL REFERENCES forum_categories(id) ON DELETE RESTRICT,author_id UUID NOT NULL,title TEXT NOT NULL CHECK(char_length(title) BETWEEN 8 AND 160),body TEXT NOT NULL CHECK(char_length(body) BETWEEN 20 AND 8000),reply_count INT NOT NULL DEFAULT 0 CHECK(reply_count>=0),view_count BIGINT NOT NULL DEFAULT 0 CHECK(view_count>=0),is_pinned BOOLEAN NOT NULL DEFAULT false,is_locked BOOLEAN NOT NULL DEFAULT false,moderation_state TEXT NOT NULL DEFAULT 'active' CHECK(moderation_state IN('active','hidden','removed')),last_reply_at TIMESTAMPTZ,last_reply_author_id UUID,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),deleted_at TIMESTAMPTZ);
-- Listedeki varsayılan sıra: sabitlenenler üstte, sonra son hareket.
CREATE INDEX forum_topics_activity_idx ON forum_topics(is_pinned DESC,COALESCE(last_reply_at,created_at) DESC,id DESC) WHERE deleted_at IS NULL AND moderation_state='active';
CREATE INDEX forum_topics_category_idx ON forum_topics(category_id,COALESCE(last_reply_at,created_at) DESC,id DESC) WHERE deleted_at IS NULL AND moderation_state='active';
CREATE INDEX forum_topics_replies_idx ON forum_topics(reply_count DESC,id DESC) WHERE deleted_at IS NULL AND moderation_state='active';
CREATE INDEX forum_topics_author_idx ON forum_topics(author_id,created_at DESC);

CREATE TABLE forum_replies (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),topic_id UUID NOT NULL REFERENCES forum_topics(id) ON DELETE CASCADE,author_id UUID NOT NULL,body TEXT NOT NULL CHECK(char_length(body) BETWEEN 1 AND 4000),is_accepted_answer BOOLEAN NOT NULL DEFAULT false,moderation_state TEXT NOT NULL DEFAULT 'active' CHECK(moderation_state IN('active','hidden','removed')),created_at TIMESTAMPTZ NOT NULL DEFAULT now(),deleted_at TIMESTAMPTZ);
CREATE INDEX forum_replies_topic_idx ON forum_replies(topic_id,created_at,id) WHERE deleted_at IS NULL AND moderation_state='active';
-- Bir konunun işaretlenmiş tek bir cevabı olur; soruyu soranın kararı.
CREATE UNIQUE INDEX forum_replies_accepted_idx ON forum_replies(topic_id) WHERE is_accepted_answer AND deleted_at IS NULL;

-- Beğeni konuda da yanıtta da aynı kayıt; ayrı iki tablo tutmak, iki yerde
-- aynı sayma sorgusunu yazmak demekti.
CREATE TABLE forum_reactions (target_type TEXT NOT NULL CHECK(target_type IN('topic','reply')),target_id UUID NOT NULL,actor_id UUID NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),PRIMARY KEY(target_type,target_id,actor_id));
CREATE INDEX forum_reactions_target_idx ON forum_reactions(target_type,target_id);

-- Okunma sayacı bir tıklama sayacı değil: aynı üyenin konuyu tekrar açması
-- sayıyı artırmıyor. Sayaç forum_topics.view_count'ta, bu tablo yalnızca
-- "bu üye bunu daha önce açtı mı" sorusunu yanıtlıyor.
CREATE TABLE forum_topic_views (topic_id UUID NOT NULL REFERENCES forum_topics(id) ON DELETE CASCADE,viewer_id UUID NOT NULL,first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),PRIMARY KEY(topic_id,viewer_id));

INSERT INTO forum_categories(slug,title,emoji,description,ordinal) VALUES
  ('vize-gocmenlik','Vize & Göçmenlik','🎓','Vize türleri, yeşil kart, vatandaşlık ve randevular',1),
  ('emlak-yasam','Emlak & Yaşam','🏠','Kiralama, ev alma, mahalleler ve taşınma',2),
  ('is-kurma-yatirim','İş Kurma & Yatırım','💼','Şirket kurma, vergi, işletme devri ve yatırım',3),
  ('egitim-okul','Eğitim & Okul','📚','Okul kayıtları, üniversite ve çocuklar için Türkçe',4),
  ('gunluk-hayat','Günlük Hayat','🛒','Ehliyet, sağlık, alışveriş ve şehirdeki pratik bilgiler',5)
ON CONFLICT (slug) DO NOTHING;
