-- Gurbet Yolculugu: badges, XP, levels and the weekly leaderboard.
--
-- The app already showed three badges on the profile - "Paterson Veteran",
-- "3. Yil", "Sila Hasreti" - and all three were string literals in
-- MockProfileRepository. Nobody could earn one, lose one, or find out what any
-- of them meant. This migration is what makes a badge a fact about a member
-- instead of a decoration.
--
-- Design notes that matter later:
--   * The catalogue is data, not code. Adding a badge is an INSERT, so a badge
--     can ship without a client release and an old client that does not know an
--     icon name falls back to a generic one.
--   * Every award path is idempotent (ON CONFLICT DO NOTHING on a natural key).
--     The award engine runs from an at-least-once outbox consumer, so "the same
--     event arrived twice" must not mean "two badges" or "double XP".
--   * Points are stored on the definition and summed into member_scores rather
--     than being incremented in place. A miscounted increment is unrecoverable;
--     a sum can always be recomputed from member_badges.

-- --- Catalogue ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS badge_definitions (
  code TEXT PRIMARY KEY CHECK (code ~ '^[a-z0-9_]{3,60}$'),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 2 AND 60),
  description TEXT NOT NULL CHECK (char_length(description) BETWEEN 5 AND 240),
  -- A Material icon name the client maps to a glyph. Stored as text so the
  -- catalogue stays data; an unknown name renders as the default badge icon.
  icon TEXT NOT NULL DEFAULT 'workspace_premium',
  category TEXT NOT NULL CHECK (category IN ('onboarding', 'social', 'expert', 'legendary', 'secret')),
  tier TEXT NOT NULL CHECK (tier IN ('bronze', 'silver', 'gold', 'legendary')),
  points INTEGER NOT NULL CHECK (points BETWEEN 0 AND 5000),
  -- A secret badge's criteria are never sent to the client before it is earned.
  -- The row is still readable so the profile can show "kilitli" slots and a
  -- count, which is the point of a hidden achievement rather than an absent one.
  is_secret BOOLEAN NOT NULL DEFAULT FALSE,
  -- Some awards are a human decision, not a rule: the solidarity medal is given
  -- by an administrator. Marking them keeps the engine from ever trying to
  -- evaluate a criterion that does not exist.
  manual_only BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS member_badges (
  user_id UUID NOT NULL,
  badge_code TEXT NOT NULL REFERENCES badge_definitions(code) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_code)
);

-- Weekly leaderboards and the "kazanildi" toast both read by time, and rarity
-- reads by badge.
CREATE INDEX IF NOT EXISTS member_badges_earned_idx ON member_badges (earned_at DESC);
CREATE INDEX IF NOT EXISTS member_badges_badge_idx ON member_badges (badge_code);

-- Counters for badges that are not a single yes/no event: "5 farkli gonderi",
-- "10 kisiyle sohbet", "14 gun ust uste". Kept separate from member_badges so a
-- progress bar can exist before the badge does, which is the whole dopamine
-- loop: the member sees 3/5, not nothing.
CREATE TABLE IF NOT EXISTS member_badge_progress (
  user_id UUID NOT NULL,
  badge_code TEXT NOT NULL REFERENCES badge_definitions(code) ON DELETE CASCADE,
  current INTEGER NOT NULL DEFAULT 0 CHECK (current >= 0),
  target INTEGER NOT NULL CHECK (target > 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_code)
);

-- --- Score, level and streak --------------------------------------------

CREATE TABLE IF NOT EXISTS member_scores (
  user_id UUID PRIMARY KEY,
  points INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0),
  level SMALLINT NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 50),
  badge_count INTEGER NOT NULL DEFAULT 0 CHECK (badge_count >= 0),
  -- Denormalised from the profile projection so the leaderboard is one index
  -- scan rather than a join across every member in the state. Rewritten by the
  -- projection worker whenever locality changes.
  city TEXT,
  region_code TEXT CHECK (region_code ~ '^[A-Z]{2}$'),
  -- Duolingo mechanics: the chain breaks if a day is skipped, and the best run
  -- is kept because losing it entirely is the kind of thing that makes people
  -- stop caring about the chain at all.
  streak_days INTEGER NOT NULL DEFAULT 0 CHECK (streak_days >= 0),
  streak_best INTEGER NOT NULL DEFAULT 0 CHECK (streak_best >= 0),
  last_active_on DATE,
  -- Anti-abuse. VIP perks (free spotlight, priority reports, unlimited DM) are
  -- suspended rather than revoked: 60 days of silence or a moderation warning
  -- freezes them, and coming back unfreezes them. A permanent loss would punish
  -- a holiday the same as an abuse.
  perks_frozen_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS member_scores_region_idx ON member_scores (region_code, points DESC);
CREATE INDEX IF NOT EXISTS member_scores_city_idx ON member_scores (region_code, city, points DESC);

-- Levels are static data rather than a formula in application code so the
-- client can render the whole ladder ("sonraki seviyeye 240 XP") without
-- knowing the curve, and so changing the curve is a migration with a diff.
CREATE TABLE IF NOT EXISTS journey_levels (
  level SMALLINT PRIMARY KEY CHECK (level BETWEEN 1 AND 50),
  title TEXT NOT NULL,
  min_points INTEGER NOT NULL CHECK (min_points >= 0)
);

-- floor(50 * (level-1)^1.5): one bronze badge (50 XP) is enough for level 2, the
-- named milestones land where the design says they should - Permanent Resident
-- around 1.350 XP, Mahalle Muhtari around 5.880, Gurbet Efsanesi around 17.150 -
-- and the top of the ladder stays under the catalogue's total.
INSERT INTO journey_levels (level, title, min_points)
SELECT level, 'Gurbetci', floor(50 * power(level - 1, 1.5))::int
  FROM generate_series(1, 50) AS level
ON CONFLICT (level) DO NOTHING;

UPDATE journey_levels SET title = 'Fresh off the Boat'   WHERE level = 1;
UPDATE journey_levels SET title = 'Local Explorer'        WHERE level = 2;
UPDATE journey_levels SET title = 'Yeni Komsu'            WHERE level BETWEEN 3 AND 9;
UPDATE journey_levels SET title = 'Permanent Resident'    WHERE level = 10;
UPDATE journey_levels SET title = 'Yerlesik Gurbetci'     WHERE level BETWEEN 11 AND 24;
UPDATE journey_levels SET title = 'Local Turk'            WHERE level = 25;
UPDATE journey_levels SET title = 'Mahalle Muhtari'       WHERE level BETWEEN 26 AND 49;
UPDATE journey_levels SET title = 'American-Turk Legend'  WHERE level = 50;

-- --- The onboarding quest map -------------------------------------------
--
-- Four stages, three tasks each. A task is deliberately not a fifth progress
-- table: every task in the design unlocks exactly one badge, so "task done" is
-- "badge earned" and "task progress" is member_badge_progress. One source of
-- truth, and no way for a task to say complete while its badge says locked.
CREATE TABLE IF NOT EXISTS journey_stages (
  ordinal SMALLINT PRIMARY KEY,
  title TEXT NOT NULL,
  level_title TEXT NOT NULL,
  reward TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS journey_tasks (
  code TEXT PRIMARY KEY,
  stage_ordinal SMALLINT NOT NULL REFERENCES journey_stages(ordinal) ON DELETE CASCADE,
  ordinal SMALLINT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  points INTEGER NOT NULL CHECK (points >= 0),
  badge_code TEXT NOT NULL REFERENCES badge_definitions(code) ON DELETE CASCADE,
  UNIQUE (stage_ordinal, ordinal)
);

-- --- Trust on reports ---------------------------------------------------
--
-- A high-badge member's report enters the moderator queue tagged, which is the
-- first of the perks to become real. Frozen at report time for the same reason
-- due_at is: an auditor has to see the trust the reporter had when they filed,
-- not the one they have today.
ALTER TABLE content_reports
  ADD COLUMN IF NOT EXISTS reporter_trust TEXT
  CHECK (reporter_trust IS NULL OR reporter_trust IN ('standard', 'high'));

-- --- Catalogue seed -----------------------------------------------------
-- Tiers carry the XP: bronze 50, silver 150, gold 500, legendary 2000.

INSERT INTO badge_definitions (code, title, description, icon, category, tier, points, is_secret, manual_only, sort_order) VALUES
  -- Yeni gelenler & adaptasyon (bronz)
  ('jfk_welcomed',          'Ayaginin Tozuyla',      'Profilini olusturdun ve Amerika''daki sehrini haritaya isaretledin.', 'flight_land',        'onboarding', 'bronze', 50,  false, false, 1),
  ('welcome_neighbor',      'Hos Geldin Komsusu',    'Toplulukta ilk gonderini paylastin.',                                  'waving_hand',        'onboarding', 'bronze', 50,  false, false, 2),
  ('vocalist',              'Ses Ver',               'Bir gonderiye ya da hikayeye ilk yorumunu yaptin.',                    'record_voice_over',  'onboarding', 'bronze', 50,  false, false, 3),
  ('observer',              'Gozcu',                 'Bes farkli gonderiyi begendin ya da kaydettin.',                       'visibility',         'onboarding', 'bronze', 50,  false, false, 4),
  ('first_spark',           'Ilk Kivilcim',          'Ilk hikayeni paylastin.',                                              'auto_awesome',       'onboarding', 'bronze', 50,  false, false, 5),
  ('ssn_waiting_room',      'SSN Bekleme Salonu',    'Toplulukta ilk yardim sorunu actin.',                                  'help_center',        'onboarding', 'bronze', 50,  false, false, 6),
  ('dmv_survivor',          'DMV Magduru',           'Ehliyet ya da araba tecrubeni toplulukla paylastin.',                  'directions_car',     'onboarding', 'bronze', 50,  false, false, 7),
  ('market_explorer',       'Market Kasifi',         'Yakinindaki bir Turk marketini ya da kasabini onerdin.',               'storefront',         'onboarding', 'bronze', 50,  false, false, 8),
  ('first_doner_test',      'Ilk Doner Testi',       'Sehrindeki en iyi doner tartismasina ilk yorumu sen yaptin.',          'lunch_dining',       'onboarding', 'bronze', 50,  false, false, 9),
  ('zelle_venmo_friend',    'Zelle/Venmo Dostu',     'Ikinci el kategorisinde ilk etkilesimini kurdun.',                     'payments',           'onboarding', 'bronze', 50,  false, false, 10),
  ('simit_longing',         'Simit Hasreti',         'Ilk "Ozledim" etiketli hikayeni paylastin.',                           'bakery_dining',      'onboarding', 'bronze', 50,  false, false, 11),
  ('i94_clean',             'I-94 Temiz',            'Kimlik dogrulama adimlarini eksiksiz tamamladin.',                     'verified_user',      'onboarding', 'silver', 150, false, false, 12),
  ('profile_champion',      'Profil Sampiyonu',      'Fotograf, biyografi ve dogrulama - profilin eksiksiz.',                'badge',              'onboarding', 'silver', 150, false, false, 13),

  -- Sosyal & topluluk ruhu (gumus)
  ('consulate_navigator',   'Konsolosluk Fatihi',    'Pasaport ve vekalet islemleri hakkinda faydali bilgi paylastin.',      'account_balance',    'social', 'silver', 150, false, false, 20),
  ('gig_economy_leader',    'DoorDash Lideri',       'Gig-economy hakkinda rehber niteliginde bir ipucu yazdin.',            'delivery_dining',    'social', 'silver', 150, false, false, 21),
  ('mover_hunter',          'Esya Avcisi',           'Bes kisiye tasinma ve esya konusunda yardim ettin.',                   'local_shipping',     'social', 'silver', 150, false, false, 22),
  ('match_headman',         'Milli Mac Muhtari',     'Milli mac gunu izleme etkinligi ya da mekan paylasimi yaptin.',        'sports_soccer',      'social', 'silver', 150, false, false, 23),
  ('sublet_lighthouse',     'Ev Arayanlara Isik',    'Sublet ve ev bulma sorularina on faydali yanit verdin.',               'holiday_village',    'social', 'silver', 150, false, false, 24),
  ('expat_gourmet',         'Gurbet Gurmesi',        'Turk lezzetine en yakin Amerikan urunlerini rehberlestirdin.',         'restaurant',         'social', 'silver', 150, false, false, 25),
  ('coffee_diplomat',       'Turk Kahvesi Diplomati','Turk kulturunu tanittigin bir hikaye paylastin.',                      'coffee',             'social', 'silver', 150, false, false, 26),
  ('salca_hunter',          'Salca Avcisi',          'Buldugun Turk urunleri paylasimi yirmiden fazla begeni aldi.',         'shopping_basket',    'social', 'silver', 150, false, false, 27),
  ('warm_tea_friend',       'Sicak Cay Dostu',       'On farkli kisiyle sohbet baslattin.',                                  'emoji_people',       'social', 'silver', 150, false, false, 28),
  ('community_beacon',      'Topluluk Feneri',       'Bir gonderin elli begeni ya da yirmi yorum aldi.',                     'lightbulb',          'social', 'silver', 150, false, false, 29),
  ('content_machine',       'Kirk Ambar',            'Toplam elli ozgun gonderi ya da hikaye paylastin.',                    'inventory_2',        'social', 'silver', 150, false, false, 30),
  ('streak_master_14',      'Seri Mudavim',          'On dort gun araliksiz girip her gun en az bir etkilesim yaptin.',      'local_fire_department','social','silver', 150, false, false, 31),

  -- Uzman & katkici (altin)
  ('visa_guru',             'Vize Gurusu',           'Vize sorularina verdigin yanit "En Faydali" secildi.',                 'workspace_premium',  'expert', 'gold', 500, false, false, 40),
  ('tax_season_survivor',   'IRS ile Barisik',      'Vergi doneminde muhasebe ipuclarini toplulukla paylastin.',            'receipt_long',       'expert', 'gold', 500, false, false, 41),
  ('state_guide',           'Eyalet Rehberi',        'Yasadigin eyalet icin uctan uca kapsamli bir rehber yazdin.',          'map',                'expert', 'gold', 500, false, false, 42),
  ('neighborhood_sentinel', 'Mahalle Bekcisi',       'Kurallara aykiri on icerigi dogru sekilde raporladin.',                'shield',             'expert', 'gold', 500, false, false, 43),
  ('streak_master_30',      'Otuz Gunluk Zincir',    'Otuz gun araliksiz her gun uygulamaya girdin.',                        'whatshot',           'expert', 'gold', 500, false, false, 44),
  ('network_master',        'Network Ustadi',        'Platformdan tanistigin bes kisiyle gercek hayatta bulustun.',          'groups',             'expert', 'gold', 500, false, false, 45),
  ('career_angel',          'Kariyer Melegi',        'Universite ve is basvurusu sureclerinde genclere mentorluk ettin.',    'school',             'expert', 'gold', 500, false, false, 46),
  ('virality_god',          'Gunun Trendi',          'Bir gonderin eyaletindeki aktif uyelerin beste birinden etkilesim aldi.','trending_up',      'expert', 'gold', 500, false, false, 47),

  -- Efsanevi & prestij (elmas)
  ('the_pioneer',           'The Pioneer',           'Uygulamada birinci yilini doldurdun ve aktifligini korudun.',          'military_tech',      'legendary', 'legendary', 2000, false, false, 60),
  ('cbp_approved',          'Kusursuz Vatandas',     'Alti ay boyunca hic uyari almadin, raporlarin hep dogru cikti.',       'verified',           'legendary', 'legendary', 2000, false, false, 61),
  ('turksquare_legend',     'Turksquare Legend',     'Bes bin Gurbet XP barajini astin.',                                    'stars',              'legendary', 'legendary', 2000, false, false, 62),
  ('solidarity_medal',      'Dayanisma Madalyasi',   'Acil bir durumda toplulugu organize ettin.',                           'volunteer_activism', 'legendary', 'legendary', 2000, false, true,  63),
  ('master_chef_usa',       'Master Chef USA',       'Tarif ve inceleme paylasimlarin bin kez kaydedildi.',                  'soup_kitchen',       'legendary', 'legendary', 2000, false, false, 64),
  ('founding_architect',    'Kurucu Mimar',          'Uc yuz altmis bes gun araliksiz buradaydin.',                          'architecture',       'legendary', 'legendary', 2000, false, false, 65),
  ('community_titan',       'Topluluk Efsanesi',     'Paylasimlarin on bin begeni ve iki bin bes yuz yorum topladi.',        'emoji_events',       'legendary', 'legendary', 2000, false, false, 66),
  ('city_summit',           'Sehrin Zirvesi',        'Haftanin en aktif gurbetcisi olarak sehrinde birinci oldun.',          'leaderboard',        'legendary', 'gold',      500,  false, false, 67),

  -- Gizli basarimlar. Aciklamalar kazanildiktan sonra gosterilir.
  ('jetlag_victim',         'Jetlag Magduru',        'Bes gun ust uste gecenin ucuyle altisi arasinda paylasim yaptin.',     'bedtime',            'secret', 'silver',    150,  true, false, 80),
  ('superbowl_vs_superlig', 'Super Bowl vs Super Lig','Super Bowl gecesi derbi hakkinda paylasim yaptin.',                   'sports_football',    'secret', 'silver',    150,  true, false, 81),
  ('eid_morning_traffic',   'Bayram Namazi Trafigi', 'Bayram sabahi toplanma yerinden fotograf paylastin.',                  'mosque',             'secret', 'gold',      500,  true, false, 82),
  ('summer_bridge',         'Yaz Tatili Koprucu',    'Temmuz ile agustos arasinda "memlekete geldik" paylasimi yaptin.',     'luggage',            'secret', 'silver',    150,  true, false, 83),
  ('night_owl_legend',      'Gece Bekcisi',          'Yuz farkli gun gece ikiyle bes arasinda kaliteli paylasim yaptin.',    'nights_stay',        'secret', 'legendary', 2000, true, false, 84)
ON CONFLICT (code) DO NOTHING;

-- --- Quest map seed -----------------------------------------------------

INSERT INTO journey_stages (ordinal, title, level_title, reward) VALUES
  (1, 'Ayaginin Tozuyla',    'Fresh off the Boat', 'Kutlama efekti + bir hafta ucretsiz cerceve ozellestirme'),
  (2, 'Cevreyi Kesif',       'Local Explorer',     '"Yerel Rehber" unvani + ilk ilani ucretsiz one cikarma'),
  (3, 'Gurbetci Aliskanligi','Permanent Resident', 'Gumus rozet slotu + VIP kanal izni'),
  (4, 'Mahalle Muhtari',     'Turksquare Elite',   'Neon cerceve + oncelikli sikayet hakki')
ON CONFLICT (ordinal) DO NOTHING;

INSERT INTO journey_tasks (code, stage_ordinal, ordinal, title, description, points, badge_code) VALUES
  ('map_pin',        1, 1, 'Haritaya Igne Koy',  'Yasadigin eyaleti ve sehri sec.',                                   50,   'jfk_welcomed'),
  ('introduce_self', 1, 2, 'Kimligini Tanit',    'Profil fotografini yukle ve biyografine kisa bir sey yaz.',         100,  'profile_champion'),
  ('first_hello',    1, 3, 'Ilk Selam',          'Toplulukta ilk gonderini paylas.',                                  150,  'welcome_neighbor'),
  ('watchman',       2, 1, 'Gozcu',              'Akistaki bes farkli gonderiyi begen ya da kaydet.',                 100,  'observer'),
  ('taste_hunter',   2, 2, 'Lezzet Avcisi',      'Bir restoran ya da Turk marketi tavsiyesine yorum yap.',            150,  'expat_gourmet'),
  ('find_neighbor',  2, 3, 'Komsu Bul',          'Eyaletinden uc kisiyle baglanti kur ya da ilk mesajini at.',        200,  'warm_tea_friend'),
  ('loyalty_chain',  3, 1, 'Sadakat Zinciri',    'Uc gun araliksiz uygulamaya gir.',                                  300,  'first_spark'),
  ('be_the_light',   3, 2, 'Isik Ol',            'Yardim arayan bir gurbetcinin sorusunu yanitla.',                   250,  'consulate_navigator'),
  ('share_story',    3, 3, 'Hikayeni Paylas',    'Gunluk yasamindan ilk hikayeni paylas.',                            200,  'simit_longing'),
  ('streak_beast',   4, 1, 'Streak Canavari',    'On dort gun araliksiz gir ve her gun en az bir etkilesim yap.',     1000, 'streak_master_14'),
  ('community_lead', 4, 2, 'Topluluk Lideri',    'Bir gonderinle yirmiden fazla begeni ve yorum al.',                 1500, 'community_beacon'),
  ('safe_street',    4, 3, 'Guvenli Mahalle',    'Kurallara uymayan bir icerigi dogru sekilde raporla.',              500,  'neighborhood_sentinel')
ON CONFLICT (code) DO NOTHING;
