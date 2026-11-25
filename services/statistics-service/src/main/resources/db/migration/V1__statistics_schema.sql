-- CricKit Statistics Service / crickit_statistics
-- All tables here are rebuildable projections. IDs reference owning services; no cross-DB FKs.

CREATE TABLE statistics_processed_events (
    event_id             uuid PRIMARY KEY,
    event_type           varchar(120) NOT NULL,
    aggregate_type       varchar(80) NOT NULL,
    aggregate_id         uuid NOT NULL,
    aggregate_version    bigint,
    event_occurred_at    timestamptz,
    processed_at         timestamptz NOT NULL DEFAULT now(),
    consumer_name        varchar(100) NOT NULL,
    payload_hash         bytea
);
CREATE INDEX idx_stats_processed_aggregate ON statistics_processed_events(aggregate_type, aggregate_id, aggregate_version);
CREATE INDEX idx_stats_processed_time ON statistics_processed_events(processed_at DESC);

CREATE TABLE player_match_batting_stats (
    match_id             uuid NOT NULL,
    tournament_id        uuid,
    innings_id           uuid NOT NULL,
    innings_number       smallint NOT NULL,
    team_id              uuid NOT NULL,
    player_id            uuid NOT NULL,
    player_name_snapshot varchar(120),
    batting_position     smallint,
    runs                 integer NOT NULL DEFAULT 0 CHECK (runs >= 0),
    balls_faced          integer NOT NULL DEFAULT 0 CHECK (balls_faced >= 0),
    fours                integer NOT NULL DEFAULT 0 CHECK (fours >= 0),
    sixes                integer NOT NULL DEFAULT 0 CHECK (sixes >= 0),
    is_out               boolean NOT NULL DEFAULT false,
    dismissal_type       varchar(30),
    strike_rate          numeric(10,2) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, innings_id, player_id)
);
CREATE INDEX idx_player_match_batting_player ON player_match_batting_stats(player_id, match_id DESC);
CREATE INDEX idx_player_match_batting_tournament ON player_match_batting_stats(tournament_id, player_id) WHERE tournament_id IS NOT NULL;

CREATE TABLE player_match_bowling_stats (
    match_id             uuid NOT NULL,
    tournament_id        uuid,
    innings_id           uuid NOT NULL,
    innings_number       smallint NOT NULL,
    team_id              uuid NOT NULL,
    player_id            uuid NOT NULL,
    player_name_snapshot varchar(120),
    legal_balls          integer NOT NULL DEFAULT 0 CHECK (legal_balls >= 0),
    maidens              integer NOT NULL DEFAULT 0 CHECK (maidens >= 0),
    runs_conceded        integer NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    wickets              integer NOT NULL DEFAULT 0 CHECK (wickets >= 0),
    wides                integer NOT NULL DEFAULT 0 CHECK (wides >= 0),
    no_balls             integer NOT NULL DEFAULT 0 CHECK (no_balls >= 0),
    economy              numeric(10,2) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, innings_id, player_id)
);
CREATE INDEX idx_player_match_bowling_player ON player_match_bowling_stats(player_id, match_id DESC);
CREATE INDEX idx_player_match_bowling_tournament ON player_match_bowling_stats(tournament_id, player_id) WHERE tournament_id IS NOT NULL;

CREATE TABLE player_match_fielding_stats (
    match_id             uuid NOT NULL,
    tournament_id        uuid,
    innings_id           uuid NOT NULL,
    player_id            uuid NOT NULL,
    catches              integer NOT NULL DEFAULT 0 CHECK (catches >= 0),
    run_outs             integer NOT NULL DEFAULT 0 CHECK (run_outs >= 0),
    stumpings            integer NOT NULL DEFAULT 0 CHECK (stumpings >= 0),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, innings_id, player_id)
);
CREATE INDEX idx_player_match_fielding_player ON player_match_fielding_stats(player_id, match_id DESC);

CREATE TABLE player_match_shot_direction_stats (
    match_id             uuid NOT NULL,
    tournament_id        uuid,
    innings_id           uuid NOT NULL,
    player_id            uuid NOT NULL,
    shot_direction       varchar(30) NOT NULL,
    shots                integer NOT NULL DEFAULT 0 CHECK (shots >= 0),
    runs                 integer NOT NULL DEFAULT 0 CHECK (runs >= 0),
    boundaries           integer NOT NULL DEFAULT 0 CHECK (boundaries >= 0),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, innings_id, player_id, shot_direction)
);
CREATE INDEX idx_shot_direction_player ON player_match_shot_direction_stats(player_id, shot_direction);

CREATE TABLE player_match_bowling_zone_stats (
    match_id             uuid NOT NULL,
    tournament_id        uuid,
    innings_id           uuid NOT NULL,
    bowler_player_id     uuid NOT NULL,
    bowling_line         varchar(24) NOT NULL,
    bowling_length       varchar(24) NOT NULL,
    deliveries           integer NOT NULL DEFAULT 0 CHECK (deliveries >= 0),
    runs_conceded        integer NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    wickets              integer NOT NULL DEFAULT 0 CHECK (wickets >= 0),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, innings_id, bowler_player_id, bowling_line, bowling_length)
);
CREATE INDEX idx_bowling_zone_player ON player_match_bowling_zone_stats(bowler_player_id, bowling_line, bowling_length);

CREATE TABLE player_tournament_batting_stats (
    tournament_id        uuid NOT NULL,
    player_id            uuid NOT NULL,
    matches              integer NOT NULL DEFAULT 0 CHECK (matches >= 0),
    innings              integer NOT NULL DEFAULT 0 CHECK (innings >= 0),
    not_outs             integer NOT NULL DEFAULT 0 CHECK (not_outs >= 0),
    runs                 bigint NOT NULL DEFAULT 0 CHECK (runs >= 0),
    balls_faced          bigint NOT NULL DEFAULT 0 CHECK (balls_faced >= 0),
    fours                bigint NOT NULL DEFAULT 0 CHECK (fours >= 0),
    sixes                bigint NOT NULL DEFAULT 0 CHECK (sixes >= 0),
    highest_score        integer NOT NULL DEFAULT 0 CHECK (highest_score >= 0),
    average              numeric(12,3) NOT NULL DEFAULT 0,
    strike_rate          numeric(12,3) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tournament_id, player_id)
);
CREATE INDEX idx_tournament_batting_runs ON player_tournament_batting_stats(tournament_id, runs DESC);

CREATE TABLE player_tournament_bowling_stats (
    tournament_id        uuid NOT NULL,
    player_id            uuid NOT NULL,
    matches              integer NOT NULL DEFAULT 0 CHECK (matches >= 0),
    innings              integer NOT NULL DEFAULT 0 CHECK (innings >= 0),
    legal_balls          bigint NOT NULL DEFAULT 0 CHECK (legal_balls >= 0),
    maidens              integer NOT NULL DEFAULT 0 CHECK (maidens >= 0),
    runs_conceded        bigint NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    wickets              integer NOT NULL DEFAULT 0 CHECK (wickets >= 0),
    best_wickets         smallint NOT NULL DEFAULT 0 CHECK (best_wickets >= 0),
    best_runs_conceded   integer NOT NULL DEFAULT 0 CHECK (best_runs_conceded >= 0),
    economy              numeric(12,3) NOT NULL DEFAULT 0,
    average              numeric(12,3) NOT NULL DEFAULT 0,
    strike_rate          numeric(12,3) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tournament_id, player_id)
);
CREATE INDEX idx_tournament_bowling_wickets ON player_tournament_bowling_stats(tournament_id, wickets DESC);

CREATE TABLE player_tournament_fielding_stats (
    tournament_id        uuid NOT NULL,
    player_id            uuid NOT NULL,
    catches              integer NOT NULL DEFAULT 0 CHECK (catches >= 0),
    run_outs             integer NOT NULL DEFAULT 0 CHECK (run_outs >= 0),
    stumpings            integer NOT NULL DEFAULT 0 CHECK (stumpings >= 0),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tournament_id, player_id)
);

CREATE TABLE player_career_batting_stats (
    player_id            uuid PRIMARY KEY,
    matches              integer NOT NULL DEFAULT 0 CHECK (matches >= 0),
    innings              integer NOT NULL DEFAULT 0 CHECK (innings >= 0),
    not_outs             integer NOT NULL DEFAULT 0 CHECK (not_outs >= 0),
    runs                 bigint NOT NULL DEFAULT 0 CHECK (runs >= 0),
    balls_faced          bigint NOT NULL DEFAULT 0 CHECK (balls_faced >= 0),
    fours                bigint NOT NULL DEFAULT 0 CHECK (fours >= 0),
    sixes                bigint NOT NULL DEFAULT 0 CHECK (sixes >= 0),
    highest_score        integer NOT NULL DEFAULT 0 CHECK (highest_score >= 0),
    average              numeric(12,3) NOT NULL DEFAULT 0,
    strike_rate          numeric(12,3) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE player_career_bowling_stats (
    player_id            uuid PRIMARY KEY,
    matches              integer NOT NULL DEFAULT 0 CHECK (matches >= 0),
    innings              integer NOT NULL DEFAULT 0 CHECK (innings >= 0),
    legal_balls          bigint NOT NULL DEFAULT 0 CHECK (legal_balls >= 0),
    maidens              integer NOT NULL DEFAULT 0 CHECK (maidens >= 0),
    runs_conceded        bigint NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    wickets              integer NOT NULL DEFAULT 0 CHECK (wickets >= 0),
    best_wickets         smallint NOT NULL DEFAULT 0 CHECK (best_wickets >= 0),
    best_runs_conceded   integer NOT NULL DEFAULT 0 CHECK (best_runs_conceded >= 0),
    economy              numeric(12,3) NOT NULL DEFAULT 0,
    average              numeric(12,3) NOT NULL DEFAULT 0,
    strike_rate          numeric(12,3) NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE player_career_fielding_stats (
    player_id            uuid PRIMARY KEY,
    catches              bigint NOT NULL DEFAULT 0 CHECK (catches >= 0),
    run_outs             bigint NOT NULL DEFAULT 0 CHECK (run_outs >= 0),
    stumpings            bigint NOT NULL DEFAULT 0 CHECK (stumpings >= 0),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE statistics_rebuild_jobs (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    projection_type     varchar(50) NOT NULL CHECK (projection_type IN ('MATCH','TOURNAMENT','PLAYER_CAREER','ALL')),
    target_id           uuid,
    requested_by_user_id uuid,
    status              varchar(20) NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','RUNNING','COMPLETED','FAILED','CANCELLED')),
    started_at          timestamptz,
    completed_at        timestamptz,
    last_error          text,
    created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_stats_rebuild_queue ON statistics_rebuild_jobs(created_at) WHERE status = 'QUEUED';

COMMENT ON TABLE statistics_processed_events IS 'Inbox/deduplication ledger. Insert event ID and update projections in one transaction.';
COMMENT ON TABLE player_career_batting_stats IS 'Derived career projection; rebuildable from authoritative match events/scorecards.';
COMMENT ON TABLE player_match_shot_direction_stats IS 'Derived analytics; UNKNOWN should be counted separately rather than guessed.';
