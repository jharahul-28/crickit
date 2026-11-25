# CricKit Database Architecture and Operations Guide

## 1. Overview and Service Boundaries

CricKit is an 8-microservice platform where 5 services own dedicated, decoupled PostgreSQL 16+ relational databases:

| Service | Database Name | Default Port | Owning Responsibilities |
|---|---|---|---|
| `identity-service` | `crickit_identity` | 8081 | Global user accounts, OTP challenges, refresh token sessions, platform roles, security audit |
| `organization-service` | `crickit_organization` | 8082 | Players, teams, team memberships, captaincy leadership history, team invitations, org audit |
| `tournament-service` | `crickit_tournament` | 8083 | Tournaments, organizer roles, team registration snapshots, fixtures, standings projections |
| `match-scoring-service` | `crickit_match` | 8084 | Matches, rosters, scorer leases/fencing tokens, innings, deliveries, scorecards, corrections |
| `statistics-service` | `crickit_statistics` | 8086 | Rebuildable match, tournament, and career batting/bowling/fielding statistics projections |

Services without a PostgreSQL database:
- `load-balancer`: Spring Cloud Gateway (routing only)
- `discovery-server`: Eureka Server (in-memory registry)
- `live-service`: Spring WebFlux (Redis ephemeral pub/sub and state)

## 2. Service Database Ownership Rules

1. **Sole Writer Principle**: Only the owning service connects and writes to its database.
2. **No Cross-Database Foreign Keys**: References across services are stored as external UUIDs (e.g. `team_id`, `player_id`, `user_id`).
3. **No Cross-Database Joins**: Inter-service data retrieval is handled via REST APIs or asynchronous event streaming via Kafka.
4. **Historical Snapshots**: Where historical display stability is required (e.g., team name, player name in match rosters or tournaments), the consuming service takes an immutable display snapshot.
5. **No Tenancy Abstraction**: Global users and resource-level role grants (e.g., `team_user_roles`, `tournament_user_roles`, `match_user_roles`) are used instead of tenant IDs.

## 3. Local Setup & Initialization

### Creating Databases
Run the bootstrap SQL script as a PostgreSQL superuser:
```bash
psql -U postgres -f infrastructure/database/init/00-create-databases.sql
```

### Environment Variables
Each service configures its database connection via standard environment variables:

| Variable | Description | Default Fallback |
|---|---|---|
| `DB_URL` | JDBC URL for PostgreSQL | `jdbc:postgresql://localhost:5432/<db_name>` |
| `DB_USERNAME` | Service database username | `postgres` |
| `DB_PASSWORD` | Service database password | `postgres` |

Recommended production user assignments:
- `crickit_identity` -> `crickit_identity_app`
- `crickit_organization` -> `crickit_organization_app`
- `crickit_tournament` -> `crickit_tournament_app`
- `crickit_match` -> `crickit_match_app`
- `crickit_statistics` -> `crickit_statistics_app`

## 4. Flyway Migrations

Migrations are automatically executed by Flyway on service startup when enabled:
- Migrations path: `src/main/resources/db/migration/`
- Baseline version: `V1__<service>_schema.sql`
- In accordance with production best practices, Hibernate is set to `ddl-auto=validate`.
