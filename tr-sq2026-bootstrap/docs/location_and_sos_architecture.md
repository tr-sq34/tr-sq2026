# Location, local ranking and SOS architecture

Onboarding locality is captured once from foreground device permission during
registration, then resolved to a city and US state by the server. It is a
ranking preference, not continuous background tracking or a home address. A
New Jersey member gets a meaningful NJ boost, but national content remains
interleaved based on freshness and interests instead of being pushed to the end.
If permission is declined, the member selects a place once; afterwards the
preference changes only from Profile > Location preference.

Google Maps Platform is accessed through a TurkSquare location gateway:

- Places Autocomplete (New) provides typed suggestions using one short-lived
  session token per search.
- Place Details/Geocoding converts the selected Place ID to canonical city,
  state code and an approximate map cell.
- The mobile app submits either a foreground coordinate for initial detection
  or a Google Place ID when the member explicitly changes the preference.
  Google server keys remain in Secrets Manager and are never shipped in the app.
- Feed cards return only city/state, never precise coordinates or Place IDs.

SOS is separate sensitive functionality. It requests foreground precise
location only when the member presses SOS, uses an encrypted short-lived
incident record to locate eligible nearby recipients, and deletes the exact
point under a dedicated retention policy. It must never reuse onboarding
location or Feed/Marketplace location data.

Before SOS is enabled: add explicit consent, emergency-contact policy,
abuse/report controls, audit events and a tested expiry job.

## Feed delivery

Feed history uses cursor pagination and is therefore unbounded. New content is
delivered separately through an authenticated real-time channel; clients prepend
only eligible events and preserve the cursor snapshot while the member scrolls.
The initial rollout may use short polling, but production uses the same
authorization predicate for real-time delivery as the page query.
