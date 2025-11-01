# MusicDex — Design Document (v1.0)

## 1. Overview

**MusicDex** is a cross-platform Android/iOS app for Pokémon- and music-nerds that lets users “scan” a song they hear (like Shazam), recognize it, and add it to their personal cassette-style collection. A swipe-based UI presents recorded tracks like a Pokédex: complete entries are colored, incomplete ones are gray placeholders. Data is stored server-side per account; the backend stores **only captures and user data** and defers song/artist/album metadata to **free, public APIs**.

**Key constraints honored**

* Minimal infrastructure and code surface.
* Multi-platform app from a single codebase.
* Avoid non-free software (prefer permissive OSS and free public APIs).
* Avoid storing queryable catalogs about songs/artists; store only user captures + foreign IDs.

---

## 2. Goals & Non-Goals

### Goals

* Recognize music in the wild quickly and reliably.
* Present a playful cassette/Pokédex UI.
* Persist user captures in the cloud (no local persistence).
* Show song/artist/album details using external free APIs.
* Artist “MusicDex” view shows full discography list as Pokédex; only captured items appear “colored”.

### Non-Goals (v1)

* No social graph, sharing/trading, or leaderboards.
* No playlist sync to paid services.
* No local offline library.
* No server-side audio processing at recognition time.

---

## 3. Users & UX Targets

* **Primary**: Pokémon & music nerds who enjoy collecting.
* **Moments to shine**:

  * One-gesture record/recognize (downward swipe).
  * Satisfying cassette animations and album-sticker reveal.
  * Artist view with “caught vs. uncaught” styling.

---

## 4. High-Level Architecture

```
[Mobile App (Flutter)]
    ├─ Audio capture (mic) → Chromaprint (native lib via FFI)
    ├─ AcoustID API (recognition → MusicBrainz IDs)
    ├─ MusicBrainz + Cover Art Archive (metadata/art)
    └─ MusicDex Backend (FastAPI)
          ├─ Auth (JWT)
          ├─ Captures CRUD (user_id ↔ recording/artist/album MBIDs)
          └─ Artist-discography proxy (MB lookups; no persistence)
```

**Rationale**

* **Recognition**: Use **Chromaprint/AcoustID** (free, open ecosystem). On-device fingerprint; query AcoustID web API for matches returning **MusicBrainz IDs (MBIDs)**.
* **Metadata & Art**: **MusicBrainz** (free/open) + **Cover Art Archive** (free).
* **Mobile**: **Flutter** for single codebase and smooth custom UI.
* **Backend**: **FastAPI (Python)** fits team skills; only stores captures & users; metadata fetched live on request; optional short-lived in-memory cache.

---

## 5. External Services & Libraries (free/open)

* **Chromaprint / libchromaprint** (BSD) — on-device audio fingerprinting.
* **AcoustID API** (free key) — resolves fingerprint → MBIDs (recordings).
* **MusicBrainz API** (CC0 data) — artist/recording/album metadata.
* **Cover Art Archive** — album art by MB release IDs.
* **Flutter** (BSD-style), **Dart**, platform channels/FFI.
* **FastAPI**, **Uvicorn**, **SQLAlchemy**, **PostgreSQL**, **argon2-cffi** (password hashing), **PyJWT**.

> Note: We do **not** rely on Shazam/Spotify/Apple proprietary recognition. This keeps costs and licensing constraints minimal.

---

## 6. Mobile App (Flutter) — Feature Design

### 6.1 Navigation & Screens

* **Home (Cassette)**

  * Center cassette.
  * **Swipe down** → cassette slides into a tape deck, spindles spin, waveform animates → **record & recognize**.
  * On success: cassette ejects with **album sticker** (cover art) and title/artist marquee.
  * **Swipe up** → fresh blank cassette.
  * **Swipe left** → **Song Detail** for the current cassette.
* **Song Detail**

  * Title, artist, album, release date, location/time of capture.
  * Buttons: “Open in…” (deep link search in Apple Music/Spotify/YouTube via URI queries), “Go to Artist MusicDex”.
* **Artist MusicDex**

  * Header: artist photo (MusicBrainz/CAA if available), artist name.
  * **List**: for each recording/release group:

    1. small album image, 2) cassette icon, 3) in-artist song ID (index), 4) song name.
  * **Captured** entries: colored cassette + full info.
  * **Uncaptured**: gray cassette, “…” where unknown, only the song ID shows.
  * Uses MB API to list recordings; matched against user captures via MBIDs.

### 6.2 Recognition Flow (on device)

1. Mic capture ~10–20s LPCM.
2. Compute **Chromaprint** (fingerprint, duration).
3. Query **AcoustID** with API key, fingerprint, duration.

   * Receive candidate recordings with **recording MBIDs**, scores, and optional title/artist.
4. Pick top match above threshold; if ambiguous, show choice selector.
5. Fetch **MusicBrainz** metadata for the selected MBIDs; fetch **cover art**.
6. POST capture to backend (persist user_id + MBIDs + timestamp + geotag).

> We **do not upload raw audio** to the server. Only fingerprint → AcoustID (public API), then MBIDs.

### 6.3 Visual/Interaction Guidelines

* 60fps animations (Cassette slide, spindle spin).
* Haptics on record start/stop and on successful capture.
* Accessibility: dynamic text sizes, content labels, color-contrast for gray/colored cassettes.

---

## 7. Backend (FastAPI) — Responsibilities

### 7.1 Data Model (PostgreSQL)

* **users**

  * `id (uuid, pk)`
  * `email (unique)`, `password_hash` (argon2), `display_name`
  * `created_at`
* **captures**

  * `id (uuid, pk)`
  * `user_id (fk users.id)`
  * `recording_mbid` (uuid text) — **required**
  * `artist_mbid` (uuid text) — optional but recommended
  * `release_mbid` (uuid text) — album if available
  * `captured_at` (timestamptz)
  * `lat`, `lon` (nullable; only if user allows)
  * `raw_acoustid_score` (float) — for transparency/debug
  * `note` (nullable short text)

> **No** tables for artists/songs/albums. We intentionally avoid persistent, queryable catalogs.

### 7.2 API (JWT-secured)

**Auth**

* `POST /auth/register` — email, password → creates user.
* `POST /auth/login` — returns JWT.
* `GET  /auth/me` — user profile.

**Captures**

* `POST /captures` — body: `{ recording_mbid, artist_mbid?, release_mbid?, captured_at, lat?, lon?, raw_acoustid_score? }` → store.
* `GET  /captures` — list current user captures (paginated).
* `GET  /captures/{id}` — capture detail (plus **live** MB metadata proxy).
* `DELETE /captures/{id}` — remove capture (user-owned).

**Metadata Proxy (no persistence)**

* `GET /meta/recording/{recording_mbid}` → fetch & return MusicBrainz recording + cover art URL.
* `GET /meta/artist/{artist_mbid}/discography`

  * Returns artist discography list (recordings or release-groups) with lightweight fields.
  * Includes `captured: boolean` per row by comparing with user’s capture MBIDs.
  * Discography ordering: by first release date / canonical sort from MB.
* `GET /meta/artist/{artist_mbid}/image` → simple pass-through to best photo if available (fallback to silhouette).

**Notes**

* All `/meta/*` responses are **fetched live** from MB/CAA; optional in-memory cache (TTL 10–30 min) for rate-limit friendliness, **not** a durable store.
* Include proper **User-Agent** header and polite **1 req/sec** throttling to MusicBrainz as recommended.

### 7.3 Security & Privacy

* Passwords: Argon2id. JWT short-lived (e.g., 15m) + refresh token (HTTP-only cookie).
* CORS configured for the mobile bundle identifier schemes.
* No raw audio stored anywhere. No fingerprints stored server-side (only MBIDs + time/place).
* Location optional; if enabled, rounded to ~3–10 km grid to reduce precision if desired.

---

## 8. Data Flows (Sequences)

### 8.1 Record & Capture

1. **App**: user swipes down → capture audio → chromaprint.
2. **App → AcoustID**: fingerprint + duration → candidate list (recording MBIDs).
3. **App → MB/CAA**: fetch recording/artist/release, cover art URL.
4. **App → Backend**: `POST /captures` with selected MBIDs + timestamp (+ optional lat/lon).
5. **App**: render colored cassette with album sticker.

### 8.2 Artist MusicDex Screen

1. **App → Backend**: `GET /meta/artist/{artist_mbid}/discography` (JWT).
2. **Backend**: fetch MB discography + compare with user captures; return list with `captured` flags and minimal fields (title, per-artist song index, release/year, small art URL).
3. **App**: render Pokédex-like list; gray out uncaptured.

---

## 9. Recognition Details & Tuning

* **Chromaprint parameters**: 11025 Hz mono resample, 10–20 s window for robust matching.
* **AcoustID match threshold**: start at score ≥ 0.6 (tune empirically).

  * If multiple ≥ threshold, present shortlist (title/artist) for user confirmation.
* **Disambiguation**: prefer candidates with both recording MBID + release MBID + strong score; otherwise fall back to recording MBID only.
* **Edge cases**: live versions, covers, remixes → display version note from MB where available.

---

## 10. “Listen Again” Deep-Links (no paid SDKs)

* Provide **search deep-links** rather than platform SDKs:

  * Apple Music: `music://search?q={artist} {title}` (fallback to web search if app missing).
  * Spotify: `spotify:search:{artist} {title}` (fallback web).
  * YouTube: URL intent to `https://www.youtube.com/results?search_query=...`
* Users can set default target in app settings (store only the preference).

---

## 11. Error Handling & Resilience

* **Connectivity**: If AcoustID/MB unavailable: show toast + allow retry; do **not** queue locally (per constraint), simply retry flow.
* **No match**: Show “No match” cassette with static label; offer to retry.
* **API limits**: Exponential backoff and user-agent compliance for MusicBrainz; soft cache backend responses.
* **Partial metadata**: If cover art missing, keep cassette colored but with a label sticker fallback (title text).

---

## 12. Privacy & Compliance

* Consent prompt for microphone + location (location optional).
* Explain that no audio leaves the device; only fingerprints go to AcoustID and only MBIDs are stored in MusicDex.
* GDPR: Data portability (export user captures as CSV/JSON), account deletion endpoint removing all captures.

---

## 13. Build & Tooling

### Mobile

* **Flutter** (stable).
* Plugins/FFI:

  * `flutter_sound` or minimal recorder (PCM) + custom FFI to **libchromaprint** (build for iOS/Android).
  * `http` for REST.
  * Gesture/animation via `AnimatedBuilder`, `CustomPainter` for cassette, `ImplicitlyAnimated` where possible.

### Backend

* **FastAPI**, **Uvicorn**, **SQLAlchemy**, **Alembic** (migrations), **PostgreSQL**.
* **gunicorn** + Uvicorn workers for prod.
* Rate-limit middleware for /meta passes.
* Containerized with Docker (optional).
* Deploy: small VPS or Fly.io/Railway (watch free-tier terms).

---

## 14. Data Contracts (abridged)

### Capture (client → server `POST /captures`)

```json
{
  "recording_mbid": "f27ec8db-af05-4f36-916e-3d57f91ecf5e",
  "artist_mbid": "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d",
  "release_mbid": "0e5d04e3-2a1b-4c41-8d13-9f1f4e6a2d2f",
  "captured_at": "2025-11-01T14:12:33Z",
  "lat": 45.07,
  "lon": 7.69,
  "raw_acoustid_score": 0.86
}
```

### Capture (server → client)

```json
{
  "id": "06b2a1f2-8c3a-4b32-a1ea-4e2e8a3b0b3f",
  "recording_mbid": "...",
  "artist_mbid": "...",
  "release_mbid": "...",
  "captured_at": "2025-11-01T14:12:33Z",
  "lat": 45.07,
  "lon": 7.69
}
```

### Artist Discography (server → client `GET /meta/artist/{artist_mbid}/discography`)

```json
{
  "artist": { "mbid": "...", "name": "Artist Name", "image_url": "..." },
  "items": [
    {
      "index": 1,
      "recording_mbid": "...",
      "title": "Song A",
      "release_year": 2012,
      "small_art_url": "...",
      "captured": true
    },
    {
      "index": 2,
      "recording_mbid": "...",
      "title": "Song B",
      "release_year": 2013,
      "small_art_url": null,
      "captured": false
    }
  ]
}
```

---

## 15. Security Checklist

* Argon2id password hashing, salted.
* JWT access + refresh; rotate refresh on use.
* Validate MBID format (UUID).
* Input rate limiting per user/IP.
* Strict CORS; HTTPS only.
* Store only what’s necessary; no PII beyond email/display name.
* Audit logs: auth events & destructive actions.

---

## 16. Performance & Cost

* Recognition: entirely on device; **no server compute** per scan.
* Backend: lightweight; main load is proxying MB/CAA (cacheable).
* DB size tiny (captures only).
* All chosen APIs/tools are **free/open**; AcoustID requires free API key and fair use.

---

## 17. Testing Strategy

* **Unit**: chromaprint FFI, AcoustID client, MB proxy mappers.
* **Integration**: end-to-end scan (use prerecorded clips), AcoustID sandbox responses.
* **UI**: golden tests for cassette states; gesture tests for swipe up/down/left.
* **Load**: MB proxy with cache enabled; verify 1 rps courtesy rule.

---

## 18. Delivery Plan (MVP → v1)

**MVP (4–6 weeks, 2 devs)**

1. Flutter app skeleton + cassette UI + swipe gestures.
2. Mic capture → Chromaprint → AcoustID → select top match.
3. Fetch MB metadata + cover art; render sticker.
4. FastAPI backend: auth, captures POST/GET.
5. Artist view: discography proxy + captured flags (basic list, no images optional).

**v1 Polish**

* Ambiguity UI (multi-match chooser).
* Deep-link “Open in …”.
* Optional location capture + display.
* Backend caching for /meta.
* Export captures (CSV/JSON).
* Accessibility and haptics polish.

**Future (not in scope now)**

* Sharing/trading between users.
* Sign-in with Apple/Google.
* Background recognition mode.

---

## 19. Open Questions / Decisions to Confirm

1. **Artist view source**: use MB **recordings** vs **release-groups**. (Recordings better for single-track Pokédex; release-groups better for albums.)
   *Proposed*: primary view = recordings; optionally group by release-group.
2. **Geolocation precision**: store exact vs rounded.
   *Proposed*: rounded to ~2 decimals (~1–3 km) by default.
3. **Discography indexing**: deterministic per artist (stable sort by first release date, then title).
4. **AcoustID rate limits**: get a dedicated API key and implement client-side backoff.

---

## 20. Appendix: Minimal Schemas

**users**

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  display_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**captures**

```sql
CREATE TABLE captures (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recording_mbid UUID NOT NULL,
  artist_mbid UUID,
  release_mbid UUID,
  captured_at TIMESTAMPTZ NOT NULL,
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  raw_acoustid_score DOUBLE PRECISION,
  CHECK ((lat IS NULL AND lon IS NULL) OR (lat BETWEEN -90 AND 90 AND lon BETWEEN -180 AND 180))
);
CREATE INDEX ON captures (user_id, recording_mbid);
```

---

### Final Notes

* This design keeps infrastructure minimal, leverages **free/open** recognition (Chromaprint/AcoustID) and metadata (MusicBrainz/CAA), and stores **only** user captures and identifiers.
* Flutter + FastAPI aligns with the team’s Python strength while keeping the client truly cross-platform.
* The cassette-centric UX is core and fully supported by the architecture without proprietary SDK dependencies.
