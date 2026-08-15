-- Group profile and invited members.
--
-- Two things were missing for a group to be run by the person who created it.
--
-- The first is a description. A name and a city say where a group is, not what
-- it is for: "New York Türkleri" could be a newcomer help desk or a football
-- crowd, and somebody deciding whether to ask to join has nothing else to read.
--
-- The second is `invited`. Membership had exactly two states, and both of them
-- start with the member: they either joined a public group or asked to enter a
-- private one. An owner adding somebody is the other direction and had nowhere
-- to be recorded. Without it a private group could only ever be filled by people
-- who already knew it existed.

ALTER TABLE messaging_groups
  ADD COLUMN IF NOT EXISTS description TEXT NULL;

-- The Matrix invite is sent when the row is written, but the room membership is
-- only real once the invited user accepts. Until then this row is the only
-- record that the invite happened, which is what lets the invitee see the group
-- in their list at all.
ALTER TABLE messaging_group_members
  DROP CONSTRAINT IF EXISTS messaging_group_members_status_check;

ALTER TABLE messaging_group_members
  ADD CONSTRAINT messaging_group_members_status_check
  CHECK (status IN ('joined', 'requested', 'invited'));

-- Who added them. An owner who inherits a group needs to be able to tell an
-- invite apart from a join request, and a removed member's history should say
-- who let them in.
ALTER TABLE messaging_group_members
  ADD COLUMN IF NOT EXISTS invited_by UUID NULL;
