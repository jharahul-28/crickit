-- CricKit Tournament Service / crickit_tournament
-- Tournaments, organizer roles, team registrations, fixtures and standings projections.

CREATE TABLE tournaments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                varchar(160) NOT NULL,
    description         varchar(2000),
    format              varchar(30) NOT NULL CHECK (format IN ('SINGLE_ROUND_ROBIN','MANUAL_FIXTURES')),
    status              varchar(24) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','REGISTRATION_OPEN','SCHEDULED','LIVE','COMPLETED','CANCELLED')),
    overs_per_innings   smallint NOT NULL CHECK (overs_per_innings BETWEEN 1 AND 100),
    balls_per_over      smallint NOT NULL DEFAULT 6 CHECK (balls_per_over BETWEEN 1 AND 12),
    max_overs_per_bowler smallint,
    innings_per_team    smallint NOT NULL DEFAULT 1 CHECK (innings_per_team IN (1,2)),
    points_for_win      smallint NOT NULL DEFAULT 2 CHECK (points_for_win >= 0),
    points_for_tie      smallint NOT NULL DEFAULT 1 CHECK (points_for_tie >= 0),
    points_for_no_result smallint NOT NULL DEFAULT 1 CHECK (points_for_no_result >= 0),
    timezone_id         varchar(64) NOT NULL DEFAULT 'UTC',
    registration_opens_at timestamptz,
    registration_closes_at timestamptz,
    starts_at           timestamptz,
    ends_at             timestamptz,
    ruleset_code        varchar(60) NOT NULL DEFAULT 'CRICKET_LIMITED_OVERS',
    ruleset_version     varchar(30) NOT NULL DEFAULT 'MCC_2026_BASELINE',
    configuration       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id  uuid NOT NULL, -- external identity id
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    completed_at        timestamptz,
    CONSTRAINT ck_tournament_bowler_overs CHECK (max_overs_per_bowler IS NULL OR (max_overs_per_bowler > 0 AND max_overs_per_bowler <= overs_per_innings)),
    CONSTRAINT ck_tournament_dates CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at),
    CONSTRAINT ck_registration_dates CHECK (registration_closes_at IS NULL OR registration_opens_at IS NULL OR registration_closes_at >= registration_opens_at)
);
CREATE INDEX idx_tournaments_status_start ON tournaments(status, starts_at);
CREATE INDEX idx_tournaments_creator ON tournaments(created_by_user_id, created_at DESC);

CREATE TABLE tournament_user_roles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id       uuid NOT NULL REFERENCES tournaments(id),
    user_id             uuid NOT NULL, -- external identity id
    role                varchar(30) NOT NULL CHECK (role IN ('OWNER','ORGANIZER','TOURNAMENT_MANAGER')),
    assigned_by_user_id uuid NOT NULL,
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT ck_tournament_role_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_tournament_user_active_role ON tournament_user_roles(tournament_id, user_id, role) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX uq_tournament_single_active_owner ON tournament_user_roles(tournament_id) WHERE role = 'OWNER' AND revoked_at IS NULL;
CREATE INDEX idx_tournament_roles_user ON tournament_user_roles(user_id, tournament_id) WHERE revoked_at IS NULL;

CREATE TABLE tournament_teams (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id       uuid NOT NULL REFERENCES tournaments(id),
    team_id             uuid NOT NULL, -- external crickit_organization.teams.id
    team_name_snapshot  varchar(120) NOT NULL,
    team_short_name_snapshot varchar(20),
    registration_status varchar(20) NOT NULL DEFAULT 'REGISTERED' CHECK (registration_status IN ('INVITED','REGISTERED','WITHDRAWN','DISQUALIFIED')),
    seed_number         smallint,
    registered_by_user_id uuid NOT NULL,
    registered_at       timestamptz NOT NULL DEFAULT now(),
    withdrawn_at        timestamptz,
    CONSTRAINT uq_tournament_team UNIQUE (tournament_id, team_id),
    CONSTRAINT uq_tournament_registration_id UNIQUE (tournament_id, id)
);
CREATE INDEX idx_tournament_teams_status ON tournament_teams(tournament_id, registration_status);

CREATE TABLE tournament_scorer_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id       uuid NOT NULL REFERENCES tournaments(id),
    user_id             uuid NOT NULL, -- external identity id
    assigned_by_user_id uuid NOT NULL,
    status              varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED')),
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT uq_tournament_scorer_assignment UNIQUE (tournament_id, user_id, assigned_at),
    CONSTRAINT ck_tournament_scorer_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE INDEX idx_tournament_scorers_active ON tournament_scorer_assignments(tournament_id, user_id) WHERE status = 'ACTIVE';

CREATE TABLE fixtures (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id       uuid NOT NULL REFERENCES tournaments(id),
    round_number        smallint,
    fixture_number      integer NOT NULL,
    home_team_id        uuid NOT NULL,
    away_team_id        uuid NOT NULL,
    scheduled_at        timestamptz,
    venue_name_snapshot varchar(160),
    venue_address_snapshot varchar(500),
    status              varchar(24) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SCHEDULED','POSTPONED','RESCHEDULED','IN_PROGRESS','COMPLETED','ABANDONED','CANCELLED')),
    provisioning_status varchar(20) NOT NULL DEFAULT 'PENDING' CHECK (provisioning_status IN ('PENDING','PROVISIONING','PROVISIONED','FAILED')),
    match_id            uuid, -- external crickit_match.matches.id, nullable until provisioned
    provisioning_error text,
    created_by_user_id  uuid NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_fixture_home_registration FOREIGN KEY (tournament_id, home_team_id) REFERENCES tournament_teams(tournament_id, team_id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_fixture_away_registration FOREIGN KEY (tournament_id, away_team_id) REFERENCES tournament_teams(tournament_id, team_id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT ck_fixture_distinct_teams CHECK (home_team_id <> away_team_id),
    CONSTRAINT uq_fixture_number UNIQUE (tournament_id, fixture_number)
);
CREATE UNIQUE INDEX uq_fixture_pair_once ON fixtures(tournament_id, LEAST(home_team_id, away_team_id), GREATEST(home_team_id, away_team_id)) WHERE status <> 'CANCELLED';
CREATE UNIQUE INDEX uq_fixture_match_id ON fixtures(match_id) WHERE match_id IS NOT NULL;
CREATE INDEX idx_fixtures_schedule ON fixtures(tournament_id, scheduled_at);
CREATE INDEX idx_fixtures_provisioning ON fixtures(provisioning_status, created_at) WHERE provisioning_status <> 'PROVISIONED';

CREATE TABLE tournament_standings (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id       uuid NOT NULL REFERENCES tournaments(id),
    team_id             uuid NOT NULL,
    played              integer NOT NULL DEFAULT 0 CHECK (played >= 0),
    won                 integer NOT NULL DEFAULT 0 CHECK (won >= 0),
    lost                integer NOT NULL DEFAULT 0 CHECK (lost >= 0),
    tied                integer NOT NULL DEFAULT 0 CHECK (tied >= 0),
    no_result           integer NOT NULL DEFAULT 0 CHECK (no_result >= 0),
    points              integer NOT NULL DEFAULT 0,
    runs_scored         bigint NOT NULL DEFAULT 0 CHECK (runs_scored >= 0),
    balls_faced         bigint NOT NULL DEFAULT 0 CHECK (balls_faced >= 0),
    runs_conceded       bigint NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    balls_bowled        bigint NOT NULL DEFAULT 0 CHECK (balls_bowled >= 0),
    net_run_rate        numeric(12,6) NOT NULL DEFAULT 0,
    rank                integer,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_tournament_standing_team UNIQUE (tournament_id, team_id),
    CONSTRAINT ck_standings_results CHECK (played = won + lost + tied + no_result)
);
CREATE INDEX idx_tournament_standings_rank ON tournament_standings(tournament_id, rank, points DESC, net_run_rate DESC);

CREATE TABLE tournament_inbox (
    event_id             uuid PRIMARY KEY,
    event_type           varchar(120) NOT NULL,
    aggregate_id         uuid NOT NULL,
    aggregate_version    bigint,
    received_at          timestamptz NOT NULL DEFAULT now(),
    processed_at         timestamptz,
    processing_status    varchar(20) NOT NULL DEFAULT 'RECEIVED' CHECK (processing_status IN ('RECEIVED','PROCESSED','FAILED')),
    last_error           text
);
CREATE INDEX idx_tournament_inbox_unprocessed ON tournament_inbox(received_at) WHERE processing_status <> 'PROCESSED';

CREATE TABLE tournament_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type      varchar(80) NOT NULL,
    aggregate_id        uuid NOT NULL,
    aggregate_version   bigint NOT NULL DEFAULT 1 CHECK (aggregate_version > 0),
    event_type          varchar(120) NOT NULL,
    schema_version      integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    payload             jsonb NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    attempts            integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at     timestamptz NOT NULL DEFAULT now(),
    locked_by           varchar(120),
    locked_until        timestamptz,
    last_error          text
);
CREATE INDEX idx_tournament_outbox_pending ON tournament_outbox(next_attempt_at, occurred_at) WHERE published_at IS NULL;
