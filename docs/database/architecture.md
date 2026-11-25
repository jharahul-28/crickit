# CricKit Platform Database Architecture Reference

## 1. Persistence Boundaries

CricKit is designed from Day 1 as a distributed multi-microservice platform. Persistence is strictly partitioned across five relational databases and two specialized event/ephemeral tiers:

```
[ Load Balancer (Gateway) ] -> [ Services ]
                                   |
         +-------------------------+-------------------------+
         |                         |                         |
[ identity-service ]      [ organization-service ]  [ tournament-service ]
         |                         |                         |
( crickit_identity )      ( crickit_organization )  ( crickit_tournament )
         |                         |                         |
         +-------------------------+-------------------------+
                                   |
                         [ Kafka Event Bus ]
                                   |
         +-------------------------+-------------------------+
         |                                                   |
[ match-scoring-service ]                           [ statistics-service ]
         |                                                   |
  ( crickit_match )                                   ( crickit_statistics )
         |
    [ Kafka ] ---> [ live-service ] <--- ( Redis Ephemeral Cache )
```

## 2. Resource-Level Authorization Architecture

Instead of coarse-grained tenant isolation, CricKit uses global identity paired with explicit, resource-level role tables in each respective owning domain:

- **Platform Administration**: `crickit_identity.platform_user_roles` (`PLATFORM_ADMIN`, `PLATFORM_SUPPORT`)
- **Team Management**: `crickit_organization.team_user_roles` (`OWNER`, `TEAM_ADMIN`, `TEAM_MANAGER`)
- **Tournament Management**: `crickit_tournament.tournament_user_roles` (`OWNER`, `ORGANIZER`, `TOURNAMENT_MANAGER`)
- **Match Management**: `crickit_match.match_user_roles` (`OWNER`, `MATCH_MANAGER`)
- **Scoring Authority**: `crickit_match.match_scorer_assignments`, `match_scorer_sessions`, `match_scorer_leases`
- **Private Match Viewing**: `crickit_match.match_viewer_grants`
- **Team Leadership**: `crickit_organization.team_leadership_history` (`CAPTAIN`, `VICE_CAPTAIN`)

## 3. Scorer Lease and Concurrency Control

Match scoring concurrency is strictly governed by PostgreSQL:
1. **Serialization Row**: `match_state` is locked via `SELECT ... FOR UPDATE` at the beginning of each scoring transaction.
2. **Fencing Tokens**: Every lease acquisition increments a monotonic `fencing_token`.
3. **Lease Validation**: The active lease is checked against current PostgreSQL database time (`now()`), the user ID, session ID, and fencing token.
4. **Append-Only Deliveries**: The delivery ledger is immutable. Corrections are managed via `scoring_corrections` and `delivery_revisions`.
5. **Scorecard Projections**: Read models (`innings_batter_scorecard`, `innings_bowler_scorecard`) are updated transactionally alongside the delivery insert.

## 4. Event-Driven Outbox / Inbox Integration

Every database-owning service implements the Transactional Outbox pattern:
- Domain state changes and outbox event insertions commit in the same local transaction.
- Outbox workers query pending events using `FOR UPDATE SKIP LOCKED` and publish to Kafka.
- Consuming services record incoming events into an idempotency inbox table (`tournament_inbox`, `match_inbox`, `statistics_processed_events`) within the same transaction that updates projections.

## 5. Ephemeral and Gateway Layers

- **Live Service**: Pure Spring WebFlux consumer of Kafka match events. Ephemeral state and WebSocket subscriber mappings live in Redis; no PostgreSQL database is owned.
- **Load Balancer**: Stateless Spring Cloud Gateway routes traffic via Eureka discovery; no relational storage.
- **Discovery Server**: In-memory Eureka service registry; no persistence required.
