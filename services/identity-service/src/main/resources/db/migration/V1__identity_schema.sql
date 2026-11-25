-- CricKit Identity Service / crickit_identity
-- Global identity only. No tenant/workspace tables in the revised v1 architecture.

CREATE TABLE users (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164          varchar(20) NOT NULL,
    phone_verified_at   timestamptz,
    email               varchar(320),
    email_verified_at   timestamptz,
    display_name        varchar(120) NOT NULL,
    avatar_url          text,
    account_status      varchar(20) NOT NULL DEFAULT 'ACTIVE'
                        CHECK (account_status IN ('PENDING_VERIFICATION','ACTIVE','SUSPENDED','DEACTIVATED')),
    last_login_at       timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deactivated_at      timestamptz,
    CONSTRAINT uq_users_phone UNIQUE (phone_e164),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT ck_users_phone_format CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$')
);

CREATE TABLE otp_challenges (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164          varchar(20) NOT NULL,
    purpose             varchar(30) NOT NULL CHECK (purpose IN ('LOGIN','SIGNUP','PHONE_CHANGE','ACCOUNT_RECOVERY')),
    code_digest         bytea NOT NULL,
    digest_key_version  varchar(40) NOT NULL,
    expires_at          timestamptz NOT NULL,
    consumed_at         timestamptz,
    failed_attempts     smallint NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    max_attempts        smallint NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
    dispatch_status     varchar(20) NOT NULL DEFAULT 'PENDING' CHECK (dispatch_status IN ('PENDING','SENT','FAILED')),
    provider_reference  varchar(160),
    request_ip_hash     bytea,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_otp_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_otp_consumption CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);
CREATE INDEX idx_otp_phone_purpose_created ON otp_challenges(phone_e164, purpose, created_at DESC);
CREATE INDEX idx_otp_expiry_unconsumed ON otp_challenges(expires_at) WHERE consumed_at IS NULL;

CREATE TABLE refresh_sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id),
    family_id           uuid NOT NULL,
    parent_session_id   uuid REFERENCES refresh_sessions(id),
    token_hash          bytea NOT NULL UNIQUE,
    token_key_version   varchar(40) NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    last_used_at        timestamptz,
    expires_at          timestamptz NOT NULL,
    rotated_at          timestamptz,
    revoked_at          timestamptz,
    revoke_reason       varchar(40),
    replay_detected_at  timestamptz,
    user_agent          varchar(512),
    ip_hash             bytea,
    CONSTRAINT ck_refresh_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_refresh_revoke_reason CHECK (revoke_reason IS NULL OR revoke_reason IN ('LOGOUT','LOGOUT_ALL','ROTATED','REPLAY_DETECTED','ADMIN_REVOKED','USER_SUSPENDED','EXPIRED'))
);
CREATE INDEX idx_refresh_sessions_user_active ON refresh_sessions(user_id, expires_at) WHERE revoked_at IS NULL;
CREATE INDEX idx_refresh_sessions_family ON refresh_sessions(family_id);

CREATE TABLE platform_user_roles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id),
    role                varchar(40) NOT NULL CHECK (role IN ('PLATFORM_ADMIN','PLATFORM_SUPPORT')),
    assigned_by_user_id uuid REFERENCES users(id),
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    revoked_at          timestamptz,
    CONSTRAINT ck_platform_role_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_platform_user_active_role ON platform_user_roles(user_id, role) WHERE revoked_at IS NULL;

CREATE TABLE identity_security_audit (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id       uuid REFERENCES users(id),
    subject_user_id     uuid REFERENCES users(id),
    event_type          varchar(80) NOT NULL,
    outcome             varchar(20) NOT NULL CHECK (outcome IN ('SUCCESS','FAILURE','BLOCKED')),
    correlation_id      varchar(100),
    ip_hash             bytea,
    user_agent          varchar(512),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_identity_audit_subject_time ON identity_security_audit(subject_user_id, occurred_at DESC);
CREATE INDEX idx_identity_audit_event_time ON identity_security_audit(event_type, occurred_at DESC);

CREATE TABLE identity_outbox (
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
CREATE INDEX idx_identity_outbox_pending ON identity_outbox(next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX idx_identity_outbox_aggregate ON identity_outbox(aggregate_type, aggregate_id, aggregate_version);

COMMENT ON TABLE users IS 'Global application identity; resource authorization is owned by the service that owns each resource.';
COMMENT ON COLUMN otp_challenges.code_digest IS 'HMAC digest only. Never persist plaintext OTP.';
COMMENT ON COLUMN refresh_sessions.token_hash IS 'Hash of opaque refresh token; raw refresh token is returned only to the client.';
