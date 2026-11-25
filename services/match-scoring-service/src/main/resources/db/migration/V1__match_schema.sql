-- CricKit Match & Scoring Service / crickit_match
-- Authoritative match state and delivery ledger. External user/team/player/tournament IDs have no cross-DB FKs.

CREATE TABLE matches (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type         varchar(20) NOT NULL CHECK (source_type IN ('STANDALONE','TOURNAMENT')),
    tournament_id       uuid, -- external crickit_tournament.tournaments.id; null for standalone match
    fixture_id          uuid, -- external crickit_tournament.fixtures.id; null for standalone match
    created_by_user_id  uuid NOT NULL, -- external crickit_identity.users.id
    format              varchar(24) NOT NULL DEFAULT 'LIMITED_OVERS' CHECK (format IN ('LIMITED_OVERS','CUSTOM_LIMITED_OVERS')),
    visibility          varchar(20) NOT NULL DEFAULT 'PUBLIC' CHECK (visibility IN ('PUBLIC','UNLISTED','PRIVATE')),
    status              varchar(24) NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','READY','IN_PROGRESS','INNINGS_BREAK','SUSPENDED','COMPLETED','TIED','ABANDONED','CANCELLED')),
    scheduled_at        timestamptz,
    started_at          timestamptz,
    ended_at            timestamptz,
    venue_name           varchar(160),
    venue_address        varchar(500),
    overs_per_innings   smallint NOT NULL CHECK (overs_per_innings BETWEEN 1 AND 100),
    balls_per_over      smallint NOT NULL DEFAULT 6 CHECK (balls_per_over BETWEEN 1 AND 12),
    max_overs_per_bowler smallint,
    innings_per_team    smallint NOT NULL DEFAULT 1 CHECK (innings_per_team IN (1,2)),
    super_over_enabled  boolean NOT NULL DEFAULT false,
    ruleset_code        varchar(60) NOT NULL DEFAULT 'CRICKET_LIMITED_OVERS',
    ruleset_version     varchar(40) NOT NULL DEFAULT 'MCC_2026_BASELINE',
    ruleset_snapshot    jsonb NOT NULL DEFAULT '{}'::jsonb,
    toss_winner_team_id uuid,
    toss_decision       varchar(10) CHECK (toss_decision IS NULL OR toss_decision IN ('BAT','BOWL')),
    result_type         varchar(24) CHECK (result_type IS NULL OR result_type IN ('WIN_BY_RUNS','WIN_BY_WICKETS','TIE','NO_RESULT','ABANDONED','SUPER_OVER')),
    winner_team_id      uuid,
    result_margin       integer CHECK (result_margin IS NULL OR result_margin >= 0),
    result_summary      varchar(500),
    current_innings_number smallint NOT NULL DEFAULT 0 CHECK (current_innings_number >= 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_match_source_reference CHECK ((source_type = 'STANDALONE' AND tournament_id IS NULL AND fixture_id IS NULL) OR (source_type = 'TOURNAMENT' AND tournament_id IS NOT NULL AND fixture_id IS NOT NULL)),
    CONSTRAINT ck_match_bowler_overs CHECK (max_overs_per_bowler IS NULL OR (max_overs_per_bowler > 0 AND max_overs_per_bowler <= overs_per_innings)),
    CONSTRAINT ck_match_toss_pair CHECK ((toss_winner_team_id IS NULL AND toss_decision IS NULL) OR (toss_winner_team_id IS NOT NULL AND toss_decision IS NOT NULL)),
    CONSTRAINT ck_match_time_order CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX idx_matches_status_schedule ON matches(status, scheduled_at);
CREATE INDEX idx_matches_tournament ON matches(tournament_id, scheduled_at) WHERE tournament_id IS NOT NULL;
CREATE INDEX idx_matches_creator ON matches(created_by_user_id, created_at DESC);

CREATE TABLE match_teams (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    team_id             uuid NOT NULL, -- external crickit_organization.teams.id
    side                varchar(8) NOT NULL CHECK (side IN ('HOME','AWAY')),
    team_name_snapshot  varchar(120) NOT NULL,
    short_name_snapshot varchar(20),
    captain_player_id   uuid, -- external crickit_organization.players.id
    vice_captain_player_id uuid,
    roster_version      varchar(80),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_match_team UNIQUE (match_id, team_id),
    CONSTRAINT uq_match_side UNIQUE (match_id, side),
    CONSTRAINT uq_match_team_composite UNIQUE (match_id, id)
);

ALTER TABLE matches ADD CONSTRAINT fk_match_toss_winner_team FOREIGN KEY (id, toss_winner_team_id) REFERENCES match_teams(match_id, team_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE matches ADD CONSTRAINT fk_match_result_winner_team FOREIGN KEY (id, winner_team_id) REFERENCES match_teams(match_id, team_id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE match_user_roles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    user_id             uuid NOT NULL, -- external crickit_identity.users.id
    role                varchar(24) NOT NULL CHECK (role IN ('OWNER','MATCH_MANAGER')),
    assigned_by_user_id uuid NOT NULL,
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT ck_match_role_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_match_user_active_role ON match_user_roles(match_id, user_id, role) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX uq_match_single_owner ON match_user_roles(match_id) WHERE role = 'OWNER' AND revoked_at IS NULL;
CREATE INDEX idx_match_roles_user ON match_user_roles(user_id, match_id) WHERE revoked_at IS NULL;

CREATE TABLE match_viewer_grants (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    user_id             uuid NOT NULL,
    granted_by_user_id  uuid NOT NULL,
    granted_at          timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT ck_viewer_grant_dates CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);
CREATE UNIQUE INDEX uq_match_viewer_active ON match_viewer_grants(match_id, user_id) WHERE revoked_at IS NULL;

CREATE TABLE match_scorer_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    user_id             uuid NOT NULL, -- external crickit_identity.users.id
    assigned_by_user_id uuid NOT NULL,
    assignment_status   varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (assignment_status IN ('ACTIVE','REVOKED')),
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT uq_match_scorer_assignment UNIQUE (match_id, user_id, assigned_at),
    CONSTRAINT uq_match_scorer_assignment_identity UNIQUE (match_id, id, user_id),
    CONSTRAINT ck_scorer_assignment_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE INDEX idx_match_scorers_active ON match_scorer_assignments(match_id, user_id) WHERE assignment_status = 'ACTIVE';

CREATE TABLE match_scorer_sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    assignment_id       uuid NOT NULL,
    user_id             uuid NOT NULL,
    fencing_token       bigint NOT NULL CHECK (fencing_token > 0),
    session_status      varchar(20) NOT NULL CHECK (session_status IN ('ACTIVE','RELEASED','EXPIRED','REVOKED','SUPERSEDED')),
    acquired_at         timestamptz NOT NULL DEFAULT now(),
    last_heartbeat_at   timestamptz,
    lease_expires_at    timestamptz NOT NULL,
    released_at         timestamptz,
    termination_reason  varchar(40),
    CONSTRAINT fk_scorer_session_assignment FOREIGN KEY (match_id, assignment_id, user_id) REFERENCES match_scorer_assignments(match_id, id, user_id),
    CONSTRAINT uq_match_fencing_token UNIQUE (match_id, fencing_token),
    CONSTRAINT uq_scorer_session_match_id_user_token UNIQUE (match_id, id, user_id, fencing_token),
    CONSTRAINT ck_scorer_session_expiry CHECK (lease_expires_at > acquired_at)
);
CREATE INDEX idx_scorer_sessions_match_time ON match_scorer_sessions(match_id, acquired_at DESC);
CREATE INDEX idx_scorer_sessions_user_time ON match_scorer_sessions(user_id, acquired_at DESC);

-- One durable current lease row per match. Acquire/renew/release must lock this row and use database time.
CREATE TABLE match_scorer_leases (
    match_id            uuid PRIMARY KEY REFERENCES matches(id),
    session_id          uuid,
    user_id             uuid,
    fencing_token       bigint NOT NULL DEFAULT 0 CHECK (fencing_token >= 0),
    lease_expires_at    timestamptz,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_scorer_lease_pair CHECK ((session_id IS NULL AND user_id IS NULL AND lease_expires_at IS NULL) OR (session_id IS NOT NULL AND user_id IS NOT NULL AND lease_expires_at IS NOT NULL)),
    CONSTRAINT fk_scorer_lease_session_owner FOREIGN KEY (match_id, session_id, user_id, fencing_token) REFERENCES match_scorer_sessions(match_id, id, user_id, fencing_token)
);

CREATE TABLE match_players (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    match_team_id       uuid NOT NULL,
    player_id           uuid NOT NULL, -- external crickit_organization.players.id
    player_name_snapshot varchar(120) NOT NULL,
    primary_role_snapshot varchar(30),
    batting_style_snapshot varchar(30),
    bowling_style_snapshot varchar(40),
    is_playing_xi       boolean NOT NULL DEFAULT false,
    is_substitute       boolean NOT NULL DEFAULT false,
    batting_order       smallint,
    roster_version      varchar(80),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_match_player_team FOREIGN KEY (match_id, match_team_id) REFERENCES match_teams(match_id, id),
    CONSTRAINT uq_match_player UNIQUE (match_id, player_id),
    CONSTRAINT uq_match_player_team UNIQUE (match_id, match_team_id, player_id),
    CONSTRAINT ck_match_player_batting_order CHECK (batting_order IS NULL OR batting_order BETWEEN 1 AND 20)
);
CREATE UNIQUE INDEX uq_match_team_playing_batting_order ON match_players(match_team_id, batting_order) WHERE is_playing_xi = true AND batting_order IS NOT NULL;
CREATE INDEX idx_match_players_team ON match_players(match_id, match_team_id, is_playing_xi);

CREATE TABLE match_state (
    match_id            uuid PRIMARY KEY REFERENCES matches(id),
    state_version       bigint NOT NULL DEFAULT 0 CHECK (state_version >= 0),
    current_innings_id  uuid,
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE innings (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    innings_number      smallint NOT NULL CHECK (innings_number BETWEEN 1 AND 20),
    innings_type        varchar(20) NOT NULL DEFAULT 'REGULAR' CHECK (innings_type IN ('REGULAR','SUPER_OVER')),
    super_over_number   smallint NOT NULL DEFAULT 0 CHECK (super_over_number >= 0),
    batting_team_id     uuid NOT NULL,
    bowling_team_id     uuid NOT NULL,
    innings_status      varchar(24) NOT NULL DEFAULT 'NOT_STARTED' CHECK (innings_status IN ('NOT_STARTED','IN_PROGRESS','COMPLETED','INTERRUPTED','ABANDONED')),
    overs_limit         smallint NOT NULL CHECK (overs_limit > 0),
    target_runs         integer CHECK (target_runs IS NULL OR target_runs > 0),
    total_runs          integer NOT NULL DEFAULT 0 CHECK (total_runs >= 0),
    wickets_lost        smallint NOT NULL DEFAULT 0 CHECK (wickets_lost BETWEEN 0 AND 10),
    legal_balls_bowled  integer NOT NULL DEFAULT 0 CHECK (legal_balls_bowled >= 0),
    extras_total        integer NOT NULL DEFAULT 0 CHECK (extras_total >= 0),
    completion_reason   varchar(30) CHECK (completion_reason IS NULL OR completion_reason IN ('TARGET_REACHED','ALL_OUT','OVERS_EXHAUSTED','DECLARED','FORFEIT','ABANDONED','SUPER_OVER_RESULT')),
    started_at          timestamptz,
    completed_at        timestamptz,
    state_version       bigint NOT NULL DEFAULT 0 CHECK (state_version >= 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_match_innings_number UNIQUE (match_id, innings_number),
    CONSTRAINT uq_innings_match_id UNIQUE (match_id, id),
    CONSTRAINT ck_innings_teams_distinct CHECK (batting_team_id <> bowling_team_id),
    CONSTRAINT ck_super_over_number CHECK ((innings_type = 'REGULAR' AND super_over_number = 0) OR (innings_type = 'SUPER_OVER' AND super_over_number > 0)),
    CONSTRAINT fk_innings_batting_team FOREIGN KEY (match_id, batting_team_id) REFERENCES match_teams(match_id, team_id),
    CONSTRAINT fk_innings_bowling_team FOREIGN KEY (match_id, bowling_team_id) REFERENCES match_teams(match_id, team_id),
    CONSTRAINT ck_innings_completion CHECK ((innings_status <> 'COMPLETED') OR completed_at IS NOT NULL)
);
CREATE INDEX idx_innings_match_status ON innings(match_id, innings_status, innings_number);

CREATE TABLE innings_state (
    match_id            uuid NOT NULL,
    innings_id          uuid NOT NULL,
    striker_player_id   uuid,
    non_striker_player_id uuid,
    current_bowler_player_id uuid,
    next_sequence_number integer NOT NULL DEFAULT 1 CHECK (next_sequence_number > 0),
    current_over_number smallint NOT NULL DEFAULT 0 CHECK (current_over_number >= 0),
    legal_balls_in_current_over smallint NOT NULL DEFAULT 0 CHECK (legal_balls_in_current_over >= 0),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (innings_id),
    CONSTRAINT fk_innings_state_innings FOREIGN KEY (match_id, innings_id) REFERENCES innings(match_id, id),
    CONSTRAINT fk_innings_state_striker FOREIGN KEY (match_id, striker_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT fk_innings_state_non_striker FOREIGN KEY (match_id, non_striker_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT fk_innings_state_bowler FOREIGN KEY (match_id, current_bowler_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT ck_innings_state_batters CHECK (striker_player_id IS NULL OR non_striker_player_id IS NULL OR striker_player_id <> non_striker_player_id)
);
ALTER TABLE match_state ADD CONSTRAINT fk_match_state_current_innings FOREIGN KEY (match_id, current_innings_id) REFERENCES innings(match_id, id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE deliveries (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    innings_id          uuid NOT NULL,
    sequence_number     integer NOT NULL CHECK (sequence_number > 0),
    over_number         smallint NOT NULL CHECK (over_number >= 0), -- zero-based over index
    attempt_number_in_over smallint NOT NULL CHECK (attempt_number_in_over > 0),
    legal_ball_number_in_over smallint,
    client_delivery_id  varchar(100) NOT NULL,
    state_version_before bigint NOT NULL,
    state_version_after bigint NOT NULL,
    striker_player_id   uuid NOT NULL,
    non_striker_player_id uuid NOT NULL,
    bowler_player_id    uuid NOT NULL,
    runs_off_bat        smallint NOT NULL DEFAULT 0 CHECK (runs_off_bat BETWEEN 0 AND 100),
    completed_runs      smallint NOT NULL DEFAULT 0 CHECK (completed_runs BETWEEN 0 AND 100),
    overthrow_runs      smallint NOT NULL DEFAULT 0 CHECK (overthrow_runs BETWEEN 0 AND 100),
    team_runs           smallint NOT NULL CHECK (team_runs BETWEEN 0 AND 200),
    bowler_conceded_runs smallint NOT NULL CHECK (bowler_conceded_runs BETWEEN 0 AND 200),
    is_legal_delivery   boolean NOT NULL,
    boundary_type       varchar(20) CHECK (boundary_type IS NULL OR boundary_type IN ('FOUR','SIX','ALL_RUNS_FOUR','ALL_RUNS_SIX')),
    shot_direction      varchar(30) CHECK (shot_direction IS NULL OR shot_direction IN ('THIRD_MAN','POINT','COVER','EXTRA_COVER','MID_OFF','LONG_OFF','STRAIGHT','LONG_ON','MID_ON','MID_WICKET','SQUARE_LEG','FINE_LEG','BEHIND_SQUARE','UNKNOWN')),
    bowling_line        varchar(24) CHECK (bowling_line IS NULL OR bowling_line IN ('WIDE_OUTSIDE_OFF','OUTSIDE_OFF','MIDDLE','LEG_STUMP','WIDE_OUTSIDE_LEG','UNKNOWN')),
    bowling_length      varchar(24) CHECK (bowling_length IS NULL OR bowling_length IN ('YORKER','FULL_TOSS','FULL','GOOD','BACK_OF_LENGTH','SHORT','BOUNCER','UNKNOWN')),
    adjudication_data   jsonb NOT NULL DEFAULT '{}'::jsonb,
    recorded_by_user_id uuid NOT NULL,
    scorer_session_id   uuid NOT NULL,
    scorer_fencing_token bigint NOT NULL CHECK (scorer_fencing_token > 0),
    recorded_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_delivery_match_innings FOREIGN KEY (match_id, innings_id) REFERENCES innings(match_id, id),
    CONSTRAINT uq_innings_delivery_sequence UNIQUE (innings_id, sequence_number),
    CONSTRAINT uq_match_client_delivery UNIQUE (match_id, client_delivery_id),
    CONSTRAINT uq_delivery_match_innings_id UNIQUE (match_id, innings_id, id),
    CONSTRAINT uq_delivery_state_version UNIQUE (match_id, state_version_after),
    CONSTRAINT ck_delivery_state_versions CHECK (state_version_after = state_version_before + 1),
    CONSTRAINT ck_delivery_batters_distinct CHECK (striker_player_id <> non_striker_player_id),
    CONSTRAINT fk_delivery_striker FOREIGN KEY (match_id, striker_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT fk_delivery_non_striker FOREIGN KEY (match_id, non_striker_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT fk_delivery_bowler FOREIGN KEY (match_id, bowler_player_id) REFERENCES match_players(match_id, player_id),
    CONSTRAINT fk_delivery_scorer_session FOREIGN KEY (match_id, scorer_session_id, recorded_by_user_id, scorer_fencing_token) REFERENCES match_scorer_sessions(match_id, id, user_id, fencing_token),
    CONSTRAINT ck_delivery_legal_ball_number CHECK ((is_legal_delivery AND legal_ball_number_in_over IS NOT NULL) OR (NOT is_legal_delivery AND legal_ball_number_in_over IS NULL))
);
CREATE INDEX idx_deliveries_innings_timeline ON deliveries(innings_id, sequence_number);
CREATE INDEX idx_deliveries_match_recorded ON deliveries(match_id, recorded_at DESC);
CREATE INDEX idx_deliveries_bowler ON deliveries(innings_id, bowler_player_id);

CREATE TABLE delivery_extras (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id         uuid NOT NULL REFERENCES deliveries(id),
    extra_type          varchar(20) NOT NULL CHECK (extra_type IN ('WIDE','NO_BALL','BYE','LEG_BYE','PENALTY')),
    runs                smallint NOT NULL CHECK (runs >= 0),
    conceded_by_bowler  boolean NOT NULL,
    awarded_to_team     boolean NOT NULL DEFAULT true,
    CONSTRAINT uq_delivery_extra_type UNIQUE (delivery_id, extra_type)
);

CREATE TABLE delivery_dismissals (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id         uuid NOT NULL REFERENCES deliveries(id),
    dismissal_sequence  smallint NOT NULL DEFAULT 1 CHECK (dismissal_sequence > 0),
    dismissed_player_id uuid NOT NULL,
    dismissal_type      varchar(30) NOT NULL CHECK (dismissal_type IN ('BOWLED','CAUGHT','LBW','RUN_OUT','STUMPED','HIT_WICKET','OBSTRUCTING_FIELD','HIT_BALL_TWICE','TIMED_OUT','RETIRED_OUT','RETIRED_HURT','OTHER')),
    fielder_player_id   uuid,
    catcher_player_id   uuid,
    wicketkeeper_player_id uuid,
    run_out_end         varchar(20) CHECK (run_out_end IS NULL OR run_out_end IN ('STRIKER_END','NON_STRIKER_END','UNKNOWN')),
    crossing_status     varchar(24) CHECK (crossing_status IS NULL OR crossing_status IN ('CROSSED_BEFORE_WICKET','NOT_CROSSED','UNKNOWN')),
    wicket_breaking_method varchar(24) CHECK (wicket_breaking_method IS NULL OR wicket_breaking_method IN ('HAND_OR_ARM_HOLDING_BALL','BALL','OTHER_LAWFUL_METHOD','UNKNOWN')),
    adjudicated_by_user_id uuid,
    details             jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_delivery_dismissal_sequence UNIQUE (delivery_id, dismissal_sequence)
);
CREATE INDEX idx_dismissals_player ON delivery_dismissals(dismissed_player_id, created_at DESC);

CREATE TABLE innings_non_delivery_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL,
    innings_id          uuid NOT NULL,
    event_sequence      integer NOT NULL CHECK (event_sequence > 0),
    event_type          varchar(30) NOT NULL CHECK (event_type IN ('TIMED_OUT','RETIRED_HURT','RETIRED_OUT','RETIRED','BATTER_REPLACED','PENALTY_RUNS_AWARDED')),
    player_id           uuid,
    counts_as_wicket    boolean NOT NULL DEFAULT false,
    runs_awarded        smallint NOT NULL DEFAULT 0 CHECK (runs_awarded >= 0),
    reason              varchar(1000),
    adjudicated_by_user_id uuid NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_non_delivery_event_innings FOREIGN KEY (match_id, innings_id) REFERENCES innings(match_id, id),
    CONSTRAINT uq_non_delivery_event_sequence UNIQUE (innings_id, event_sequence)
);
CREATE INDEX idx_non_delivery_events_innings ON innings_non_delivery_events(innings_id, event_sequence);

CREATE TABLE innings_batter_scorecard (
    innings_id          uuid NOT NULL REFERENCES innings(id),
    player_id           uuid NOT NULL,
    batting_position    smallint,
    runs                integer NOT NULL DEFAULT 0 CHECK (runs >= 0),
    balls_faced         integer NOT NULL DEFAULT 0 CHECK (balls_faced >= 0),
    fours               integer NOT NULL DEFAULT 0 CHECK (fours >= 0),
    sixes               integer NOT NULL DEFAULT 0 CHECK (sixes >= 0),
    is_out              boolean NOT NULL DEFAULT false,
    dismissal_type      varchar(30),
    dismissed_by_player_id uuid,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (innings_id, player_id)
);

CREATE TABLE innings_bowler_scorecard (
    innings_id          uuid NOT NULL REFERENCES innings(id),
    player_id           uuid NOT NULL,
    legal_balls         integer NOT NULL DEFAULT 0 CHECK (legal_balls >= 0),
    maidens             integer NOT NULL DEFAULT 0 CHECK (maidens >= 0),
    runs_conceded       integer NOT NULL DEFAULT 0 CHECK (runs_conceded >= 0),
    wickets             integer NOT NULL DEFAULT 0 CHECK (wickets >= 0),
    wides               integer NOT NULL DEFAULT 0 CHECK (wides >= 0),
    no_balls            integer NOT NULL DEFAULT 0 CHECK (no_balls >= 0),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (innings_id, player_id)
);

CREATE TABLE scoring_idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    user_id             uuid NOT NULL,
    idempotency_key     varchar(120) NOT NULL,
    request_hash        bytea NOT NULL,
    http_status         smallint,
    response_body       jsonb,
    delivery_id         uuid REFERENCES deliveries(id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_scoring_idempotency UNIQUE (match_id, user_id, idempotency_key)
);
CREATE INDEX idx_scoring_idempotency_created ON scoring_idempotency_records(created_at);

CREATE TABLE scoring_corrections (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    innings_id          uuid NOT NULL REFERENCES innings(id),
    delivery_id         uuid,
    requested_by_user_id uuid NOT NULL,
    approved_by_user_id uuid,
    correction_reason   varchar(1000) NOT NULL,
    correction_status   varchar(24) NOT NULL DEFAULT 'REQUESTED' CHECK (correction_status IN ('REQUESTED','APPROVED','REJECTED','APPLIED','RECONCILIATION_REQUIRED','FAILED')),
    old_facts           jsonb NOT NULL,
    proposed_new_facts  jsonb NOT NULL,
    resulting_state_version bigint,
    created_at          timestamptz NOT NULL DEFAULT now(),
    approved_at         timestamptz,
    applied_at          timestamptz,
    CONSTRAINT fk_correction_delivery_context FOREIGN KEY (match_id, innings_id, delivery_id) REFERENCES deliveries(match_id, innings_id, id)
);
CREATE INDEX idx_corrections_match_time ON scoring_corrections(match_id, created_at DESC);

CREATE TABLE delivery_revisions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id         uuid NOT NULL REFERENCES deliveries(id),
    correction_id       uuid NOT NULL REFERENCES scoring_corrections(id),
    revision_number     integer NOT NULL CHECK (revision_number > 0),
    delivery_facts      jsonb NOT NULL,
    created_by_user_id  uuid NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_delivery_revision UNIQUE (delivery_id, revision_number)
);

CREATE TABLE match_streams (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    provider            varchar(20) NOT NULL CHECK (provider IN ('YOUTUBE')),
    stream_url          text NOT NULL,
    visibility          varchar(20) NOT NULL DEFAULT 'PUBLIC' CHECK (visibility IN ('PUBLIC','UNLISTED','PRIVATE')),
    status              varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','REMOVED')),
    configured_by_user_id uuid NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_match_active_stream_provider ON match_streams(match_id, provider) WHERE status = 'ACTIVE';

CREATE TABLE match_audit_log (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id            uuid NOT NULL REFERENCES matches(id),
    actor_user_id       uuid NOT NULL,
    action              varchar(80) NOT NULL,
    resource_type       varchar(40) NOT NULL,
    resource_id         uuid,
    reason              varchar(1000),
    before_state        jsonb,
    after_state         jsonb,
    correlation_id      varchar(100),
    occurred_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_match_audit_match_time ON match_audit_log(match_id, occurred_at DESC);

CREATE TABLE match_inbox (
    event_id             uuid PRIMARY KEY,
    event_type           varchar(120) NOT NULL,
    aggregate_id         uuid NOT NULL,
    aggregate_version    bigint,
    received_at          timestamptz NOT NULL DEFAULT now(),
    processed_at         timestamptz,
    processing_status    varchar(20) NOT NULL DEFAULT 'RECEIVED' CHECK (processing_status IN ('RECEIVED','PROCESSED','FAILED')),
    last_error           text
);
CREATE INDEX idx_match_inbox_unprocessed ON match_inbox(received_at) WHERE processing_status <> 'PROCESSED';

CREATE TABLE match_outbox (
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
    last_error          text,
    CONSTRAINT uq_match_outbox_aggregate_version_event UNIQUE (aggregate_type, aggregate_id, aggregate_version, event_type)
);
CREATE INDEX idx_match_outbox_pending ON match_outbox(next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX idx_match_outbox_aggregate ON match_outbox(aggregate_type, aggregate_id, aggregate_version);

COMMENT ON TABLE deliveries IS 'Append-only authoritative delivery ledger. Correct through scoring_corrections/delivery_revisions, not in-place edits.';
COMMENT ON TABLE match_scorer_leases IS 'Durable current scorer lease. Validate fencing_token and lease_expires_at using PostgreSQL time inside the scoring transaction.';
COMMENT ON TABLE innings_batter_scorecard IS 'Rebuildable read model maintained transactionally with each accepted delivery.';
COMMENT ON TABLE innings_bowler_scorecard IS 'Rebuildable read model maintained transactionally with each accepted delivery.';
