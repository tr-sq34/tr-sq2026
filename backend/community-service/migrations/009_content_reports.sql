-- Şikâyet kuyruğu.
--
-- Uygulama bu uca bir süredir yazıyordu; tabloyu şimdi açıyoruz ki forumdan
-- gelen bildirim de paylaşımdan gelenle aynı listeye düşsün. Ayrı bir forum
-- kuyruğu açmak, moderasyon ekibine iki ayrı yere bakma yükü bindirmekti.
--
-- content_snapshot bilinçli: yazan kişi şikâyet edilen içeriği silebiliyor ve
-- ekip kuyruğu açtığında elinde hiçbir şey kalmamış oluyordu. Kopya, kaydın
-- alındığı andaki hâli.
CREATE TABLE content_reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),reporter_id UUID NOT NULL,target_type TEXT NOT NULL CHECK(target_type IN('post','comment','story','forum_topic','forum_reply')),target_id UUID NOT NULL,target_author_id UUID,category TEXT NOT NULL CHECK(category IN('child_safety','self_harm','violence_threat','hate_speech','harassment','sexual_content','scam_fraud','illegal_goods','spam','other')),note TEXT CHECK(note IS NULL OR char_length(note)<=1000),content_snapshot TEXT,state TEXT NOT NULL DEFAULT 'open' CHECK(state IN('open','reviewing','actioned','dismissed')),resolved_by UUID,resolved_at TIMESTAMPTZ,resolution_note TEXT,created_at TIMESTAMPTZ NOT NULL DEFAULT now());
-- Aynı üyenin aynı içerik için ikinci kez açtığı kayıt yeni bir şikâyet değil:
-- açık olan kaydın kendisi geri dönüyor, hata değil.
CREATE UNIQUE INDEX content_reports_open_unique_idx ON content_reports(reporter_id,target_type,target_id) WHERE state IN('open','reviewing');
CREATE INDEX content_reports_queue_idx ON content_reports(state,created_at);
-- Aynı içeriğe kaç ayrı kişiden bildirim geldiği, kuyruğun sıralamasında en
-- çok işe yarayan sayı.
CREATE INDEX content_reports_target_idx ON content_reports(target_type,target_id);

-- Moderasyon kararının üye tarafındaki karşılığı: uygulama 403'ü "işlem
-- başarısız" diye değil, sebebiyle ve bitiş tarihiyle anlatabilsin diye.
CREATE TABLE content_author_restrictions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),user_id UUID NOT NULL,kind TEXT NOT NULL CHECK(kind IN('muted','suspended')),reason TEXT NOT NULL,expires_at TIMESTAMPTZ,created_by UUID,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),lifted_at TIMESTAMPTZ);
CREATE INDEX content_author_restrictions_active_idx ON content_author_restrictions(user_id,expires_at) WHERE lifted_at IS NULL;
