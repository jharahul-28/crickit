# CricKit Platform Database Table Catalog

Total databases: 5  
Total tables: 59

---

## 1. Identity Service — `crickit_identity` (6 tables)

| Table | Purpose | Primary Key | Key Invariants / Notes |
|---|---|---|---|
| `users` | Global identity & account status | `id` (UUID) | Unique E.164 phone, unique email, phone regex check |
| `otp_challenges` | Hashed OTP challenges & lifecycle | `id` (UUID) | HMAC digest only (never plaintext), attempt counter, expiry check |
| `refresh_sessions` | Refresh tokens & token-family rotation | `id` (UUID) | Unique token hash (never plaintext), family-based rotation, replay tracking |
| `platform_user_roles` | Platform administrator & support roles | `id` (UUID) | Partial unique index for active roles (`PLATFORM_ADMIN`, `PLATFORM_SUPPORT`) |
| `identity_security_audit` | Authentication & security audit log | `id` (UUID) | JSONB metadata, outcome enum (`SUCCESS`, `FAILURE`, `BLOCKED`) |
| `identity_outbox` | Reliable identity domain event publishing | `id` (UUID) | Outbox pattern for Kafka integration, retry counter & lease locking |

---

## 2. Organization Service — `crickit_organization` (8 tables)

| Table | Purpose | Primary Key | Key Invariants / Notes |
|---|---|---|---|
| `players` | Global cricket player profiles | `id` (UUID) | Optional unique external `linked_user_id`, GIN full-text index on `display_name` |
| `teams` | Team profiles and venues | `id` (UUID) | Unique normalized name per creator, GIN full-text index on `name` |
| `team_user_roles` | Team-level RBAC (`OWNER`, `ADMIN`, `MANAGER`)| `id` (UUID) | Exactly one active `OWNER` per team enforced by partial unique index |
| `team_memberships` | Player-team memberships & jersey numbers | `id` (UUID) | Unique active membership per player-team; composite unique `(team_id, id)` |
| `team_leadership_history` | Captain and vice-captain appointments | `id` (UUID) | Points to `team_memberships`; at most one active captain & vice-captain |
| `team_invitations` | Team invitations for users/players | `id` (UUID) | Unique invitation token hash, recipient phone/user check |
| `organization_audit_log` | Team and player administration audit log | `id` (UUID) | Before/after state snapshots in JSONB |
| `organization_outbox` | Reliable org domain event publishing | `id` (UUID) | Outbox pattern for Kafka integration |

---

## 3. Tournament Service — `crickit_tournament` (8 tables)

| Table | Purpose | Primary Key | Key Invariants / Notes |
|---|---|---|---|
| `tournaments` | Tournament configuration & lifecycle | `id` (UUID) | Format (`SINGLE_ROUND_ROBIN`, `MANUAL_FIXTURES`), overs & points rules |
| `tournament_user_roles` | Tournament RBAC (`OWNER`, `ORGANIZER`, `MANAGER`) | `id` (UUID) | Exactly one active `OWNER` per tournament enforced by partial unique index |
| `tournament_teams` | Registered teams & name snapshots | `id` (UUID) | Unique `(tournament_id, team_id)`, seed numbers |
| `tournament_scorer_assignments` | Eligible tournament scorer pool | `id` (UUID) | Scorer pool assignments with active status |
| `fixtures` | Scheduled pairings & provisioning status | `id` (UUID) | Distinct team check, unique pairing index, deferred FKs to registrations |
| `tournament_standings` | Points table & Net Run Rate (NRR) | `id` (UUID) | Rebuildable projection; check constraint: `played = won + lost + tied + no_result` |
| `tournament_inbox` | Consumed event deduplication ledger | `event_id` (UUID) | Deduplication key for incoming Kafka domain events |
| `tournament_outbox` | Reliable tournament domain event publishing | `id` (UUID) | Outbox pattern for Kafka integration |

---

## 4. Match & Scoring Service — `crickit_match` (24 tables)

| Table | Purpose | Primary Key | Key Invariants / Notes |
|---|---|---|---|
| `matches` | Match configuration, lifecycle, toss & result | `id` (UUID) | Standalone vs tournament check, toss and winner deferred FKs |
| `match_teams` | Participating teams (HOME / AWAY) | `id` (UUID) | Unique `(match_id, side)`, historical team/short name snapshots |
| `match_user_roles` | Match RBAC (`OWNER`, `MATCH_MANAGER`) | `id` (UUID) | Exactly one active `OWNER` enforced by partial unique index |
| `match_viewer_grants` | Private match viewing permissions | `id` (UUID) | Explicit per-user view access for private matches |
| `match_scorer_assignments` | Assigned eligible match scorers | `id` (UUID) | Scorer eligibility assignment |
| `match_scorer_sessions` | Scorer sessions & fencing tokens | `id` (UUID) | Monotonic fencing token per match, heartbeat tracking |
| `match_scorer_leases` | Durable active scorer lease (one per match) | `match_id` (UUID) | Validated with PostgreSQL time in scoring transaction |
| `match_players` | Match team rosters & Playing XI | `id` (UUID) | Batting order check & unique playing XI batting order index |
| `match_state` | Match concurrency serialization anchor | `match_id` (UUID) | `state_version` incremented atomically with `SELECT FOR UPDATE` |
| `innings` | Innings configuration, totals & status | `id` (UUID) | Limit, target, wickets, total runs, legal balls count |
| `innings_state` | Active pitch state (striker, non-striker, bowler)| `innings_id` (UUID) | Striker != non-striker check; over & delivery sequencing |
| `deliveries` | Authoritative append-only delivery ledger | `id` (UUID) | Client delivery ID unique, state version check (`after = before + 1`) |
| `delivery_extras` | Breakdown of extras (wide, no-ball, bye, etc.)| `id` (UUID) | Unique `(delivery_id, extra_type)`, bowler/team attribution |
| `delivery_dismissals` | Dismissal details, fielders, adjudication | `id` (UUID) | Dismissal type, run out end, crossing status, method |
| `innings_non_delivery_events` | Non-delivery events (retired, timed out, penalty) | `id` (UUID) | Sequenced non-delivery match events |
| `innings_batter_scorecard` | Batter scorecard projection | `(innings_id, player_id)` | Runs, balls, 4s, 6s, dismissal details; rebuildable |
| `innings_bowler_scorecard` | Bowler figures projection | `(innings_id, player_id)` | Legal balls, maidens, runs conceded, wickets; rebuildable |
| `scoring_idempotency_records`| Command idempotency & response replay | `id` (UUID) | Request hash and cached HTTP response body |
| `scoring_corrections` | Audited scoring correction requests & workflow | `id` (UUID) | Proposed facts, review/approval status, resulting version |
| `delivery_revisions` | Immutable revision history of corrected deliveries | `id` (UUID) | Historical snapshots of delivery facts |
| `match_streams` | Live stream URL associations (e.g. YouTube) | `id` (UUID) | Provider, status, and visibility settings |
| `match_audit_log` | Match management and scoring audit trail | `id` (UUID) | Comprehensive action log with before/after state |
| `match_inbox` | Consumed event deduplication ledger | `event_id` (UUID) | Deduplication for tournament/team lifecycle events |
| `match_outbox` | Reliable match domain event publishing | `id` (UUID) | Unique `(aggregate_type, aggregate_id, aggregate_version, event_type)` |

---

## 5. Statistics Service — `crickit_statistics` (13 tables)

| Table | Purpose | Primary Key | Key Invariants / Notes |
|---|---|---|---|
| `statistics_processed_events`| Processed event deduplication ledger | `event_id` (UUID) | Consumer deduplication with payload hash |
| `player_match_batting_stats` | Match batting projection | `(match_id, innings_id, player_id)` | Runs, balls, 4s, 6s, strike rate |
| `player_match_bowling_stats` | Match bowling projection | `(match_id, innings_id, player_id)` | Balls, maidens, runs, wickets, economy |
| `player_match_fielding_stats` | Match fielding projection | `(match_id, innings_id, player_id)` | Catches, run-outs, stumpings |
| `player_match_shot_direction_stats` | Batting wagon wheel analytics | `(match_id, innings_id, player_id, shot_direction)` | Shot counts, runs, boundaries per 12 directions |
| `player_match_bowling_zone_stats` | Bowling pitch map analytics | `(match_id, innings_id, bowler_player_id, line, length)` | Deliveries, runs, wickets per line/length zone |
| `player_tournament_batting_stats` | Tournament batting aggregate | `(tournament_id, player_id)` | Runs, average, strike rate, high score |
| `player_tournament_bowling_stats` | Tournament bowling aggregate | `(tournament_id, player_id)` | Wickets, average, economy, strike rate, best figures |
| `player_tournament_fielding_stats`| Tournament fielding aggregate | `(tournament_id, player_id)` | Catches, run-outs, stumpings |
| `player_career_batting_stats` | Career batting aggregate | `player_id` (UUID) | Career runs, average, strike rate |
| `player_career_bowling_stats` | Career bowling aggregate | `player_id` (UUID) | Career wickets, average, economy, best figures |
| `player_career_fielding_stats`| Career fielding aggregate | `player_id` (UUID) | Career catches, run-outs, stumpings |
| `statistics_rebuild_jobs` | Controlled projection rebuild tracker | `id` (UUID) | Rebuild job status (`QUEUED`, `RUNNING`, `COMPLETED`, `FAILED`) |
