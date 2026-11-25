-- CricKit Organization Service / crickit_organization
-- Global player identities and resource-level team authorization.

CREATE TABLE players (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    linked_user_id      uuid UNIQUE, -- external crickit_identity.users.id; no cross-database FK
    display_name        varchar(120) NOT NULL,
    date_of_birth       date,
    batting_style       varchar(30) CHECK (batting_style IS NULL OR batting_style IN ('RIGHT_HANDED','LEFT_HANDED')),
    bowling_style       varchar(40),
    primary_role        varchar(30) CHECK (primary_role IS NULL OR primary_role IN ('BATTER','BOWLER','ALL_ROUNDER','WICKET_KEEPER')),
    profile_visibility  varchar(20) NOT NULL DEFAULT 'PUBLIC' CHECK (profile_visibility IN ('PUBLIC','PRIVATE')),
    verification_status varchar(20) NOT NULL DEFAULT 'UNVERIFIED' CHECK (verification_status IN ('UNVERIFIED','PENDING','VERIFIED','REJECTED')),
    created_by_user_id  uuid, -- external identity id
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    archived_at         timestamptz
);
CREATE INDEX idx_players_name ON players USING gin (to_tsvector('simple', display_name));
CREATE INDEX idx_players_linked_user ON players(linked_user_id) WHERE linked_user_id IS NOT NULL;

CREATE TABLE teams (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                varchar(120) NOT NULL,
    normalized_name     varchar(140) NOT NULL,
    short_name          varchar(20),
    description         varchar(1000),
    logo_url            text,
    home_venue_name     varchar(160),
    status              varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','ARCHIVED')),
    created_by_user_id  uuid NOT NULL, -- external identity id; audit attribution, not sole authorization
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    archived_at         timestamptz,
    CONSTRAINT uq_teams_normalized_name_creator UNIQUE (created_by_user_id, normalized_name)
);
CREATE INDEX idx_teams_name ON teams USING gin (to_tsvector('simple', name));

CREATE TABLE team_user_roles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             uuid NOT NULL REFERENCES teams(id),
    user_id             uuid NOT NULL, -- external identity id
    role                varchar(30) NOT NULL CHECK (role IN ('OWNER','TEAM_ADMIN','TEAM_MANAGER')),
    assigned_by_user_id uuid NOT NULL,
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT ck_team_role_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_team_user_active_role ON team_user_roles(team_id, user_id, role) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX uq_team_single_active_owner ON team_user_roles(team_id) WHERE role = 'OWNER' AND revoked_at IS NULL;
CREATE INDEX idx_team_roles_user_active ON team_user_roles(user_id, team_id) WHERE revoked_at IS NULL;

CREATE TABLE team_memberships (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             uuid NOT NULL REFERENCES teams(id),
    player_id           uuid NOT NULL REFERENCES players(id),
    jersey_number       smallint CHECK (jersey_number IS NULL OR jersey_number BETWEEN 0 AND 999),
    membership_status   varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (membership_status IN ('ACTIVE','INACTIVE','SUSPENDED')),
    joined_at           date NOT NULL DEFAULT CURRENT_DATE,
    left_at             date,
    added_by_user_id    uuid NOT NULL,
    notes               varchar(500),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_team_membership_team_id UNIQUE (team_id, id),
    CONSTRAINT ck_membership_dates CHECK (left_at IS NULL OR left_at >= joined_at)
);
CREATE UNIQUE INDEX uq_team_player_current_membership ON team_memberships(team_id, player_id) WHERE left_at IS NULL AND membership_status = 'ACTIVE';
CREATE INDEX idx_team_memberships_player ON team_memberships(player_id, joined_at DESC);
CREATE INDEX idx_team_memberships_team_status ON team_memberships(team_id, membership_status);

CREATE TABLE team_leadership_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             uuid NOT NULL REFERENCES teams(id),
    team_membership_id  uuid NOT NULL,
    leadership_role     varchar(20) NOT NULL CHECK (leadership_role IN ('CAPTAIN','VICE_CAPTAIN')),
    valid_from          timestamptz NOT NULL DEFAULT now(),
    valid_to            timestamptz,
    assigned_by_user_id uuid NOT NULL,
    reason              varchar(500),
    CONSTRAINT fk_leadership_membership FOREIGN KEY (team_id, team_membership_id) REFERENCES team_memberships(team_id, id),
    CONSTRAINT ck_leadership_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_team_current_leadership_role ON team_leadership_history(team_id, leadership_role) WHERE valid_to IS NULL;
CREATE INDEX idx_team_leadership_membership ON team_leadership_history(team_membership_id, valid_from DESC);

CREATE TABLE team_invitations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             uuid NOT NULL REFERENCES teams(id),
    invitee_phone_e164  varchar(20),
    invitee_user_id     uuid, -- external identity id; nullable until account is known
    invited_role        varchar(20) NOT NULL CHECK (invited_role IN ('TEAM_ADMIN','TEAM_MANAGER','PLAYER')),
    invitation_token_hash bytea NOT NULL UNIQUE,
    invited_by_user_id  uuid NOT NULL,
    status              varchar(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACCEPTED','DECLINED','EXPIRED','REVOKED')),
    expires_at          timestamptz NOT NULL,
    responded_at        timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_team_invite_recipient CHECK (invitee_phone_e164 IS NOT NULL OR invitee_user_id IS NOT NULL)
);
CREATE INDEX idx_team_invitations_pending ON team_invitations(team_id, expires_at) WHERE status = 'PENDING';

CREATE TABLE organization_audit_log (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id       uuid NOT NULL,
    resource_type       varchar(40) NOT NULL,
    resource_id         uuid NOT NULL,
    action              varchar(80) NOT NULL,
    before_state        jsonb,
    after_state         jsonb,
    correlation_id      varchar(100),
    occurred_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_org_audit_resource ON organization_audit_log(resource_type, resource_id, occurred_at DESC);

CREATE TABLE organization_outbox (
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
CREATE INDEX idx_org_outbox_pending ON organization_outbox(next_attempt_at, occurred_at) WHERE published_at IS NULL;
