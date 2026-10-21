-- =============================================================================
-- AbhiShare — Baseline Migration
-- =============================================================================
-- Migration : 001_baseline.sql
-- Created   : 2026-10-06
-- Purpose   : Clean baseline that reproduces the full current database schema
--             extracted directly from abhishare_dev.
--
-- Provider-neutral: uses standard PostgreSQL SQL.
-- No local-ownership (OWNER TO) statements.
-- Fresh data only: does not insert any mock/duplicate data.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extension
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- ---------------------------------------------------------------------------
-- Table: users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
    id                  uuid                        NOT NULL,
    full_name           character varying(100)      NOT NULL,
    phone               character varying(20)       NOT NULL,
    email               character varying(255)      NOT NULL,
    date_of_birth       date                        NOT NULL,
    gender              character varying(20)       NOT NULL,
    phone_verified_at   timestamp with time zone,
    email_verified_at   timestamp with time zone,
    created_at          timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at          timestamp with time zone    NOT NULL DEFAULT now(),
    pin_hash            character varying(255),
    nickname            character varying(255),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_phone_key UNIQUE (phone),
    CONSTRAINT users_email_key UNIQUE (email),
    CONSTRAINT users_gender_check CHECK (
        (gender)::text = ANY (
            ARRAY[
                'male'::character varying,
                'female'::character varying,
                'other'::character varying
            ]::text[]
        )
    )
);

-- ---------------------------------------------------------------------------
-- Table: vehicles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.vehicles (
    id                  uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id             uuid                        NOT NULL,
    vehicle_number      character varying(50)       NOT NULL,
    vehicle_type        character varying(20)       NOT NULL,
    model               character varying(100)      NOT NULL,
    rc_photo_url        text,
    vehicle_photo_url   text,
    created_at          timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at          timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT vehicles_pkey PRIMARY KEY (id),
    CONSTRAINT vehicles_vehicle_number_key UNIQUE (vehicle_number),
    CONSTRAINT vehicles_vehicle_type_check CHECK (
        (vehicle_type)::text = ANY (
            ARRAY[
                'two_wheeler'::character varying,
                'five_seater'::character varying,
                'seven_seater'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT vehicles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

-- ---------------------------------------------------------------------------
-- Table: saved_locations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_locations (
    id          uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id     uuid                        NOT NULL,
    name        character varying(255)      NOT NULL,
    address     text                        NOT NULL,
    created_at  timestamp with time zone    DEFAULT now(),
    updated_at  timestamp with time zone    DEFAULT now(),
    CONSTRAINT saved_locations_pkey PRIMARY KEY (id),
    CONSTRAINT saved_locations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- Table: recurring_schedules
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recurring_schedules (
    id                  uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id             uuid                        NOT NULL,
    recurrence_type     character varying(30)       NOT NULL,
    selected_weekdays   text[]                      DEFAULT '{}'::text[],
    start_date          date                        NOT NULL,
    end_date            date,
    occurrence_count    integer,
    ride_template       jsonb                       NOT NULL,
    status              character varying(20)       NOT NULL DEFAULT 'active'::character varying,
    created_at          timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at          timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT recurring_schedules_pkey PRIMARY KEY (id),
    CONSTRAINT recurring_schedules_status_check CHECK (
        (status)::text = ANY (
            ARRAY[
                'draft'::character varying,
                'active'::character varying,
                'paused'::character varying,
                'cancelled'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT recurring_schedules_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_recurring_schedules_user_id ON public.recurring_schedules USING btree (user_id);

-- ---------------------------------------------------------------------------
-- Table: rides
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rides (
    id                       uuid                        NOT NULL DEFAULT gen_random_uuid(),
    driver_id                uuid                        NOT NULL,
    vehicle_id               uuid                        NOT NULL,
    from_location            character varying(150)      NOT NULL,
    to_location              character varying(150)      NOT NULL,
    journey_date             date                        NOT NULL,
    departure_time           time without time zone      NOT NULL,
    estimated_arrival_time   time without time zone      NOT NULL,
    available_seats          integer                     NOT NULL,
    price_per_seat           numeric(10,2)               NOT NULL,
    status                   character varying(20)       NOT NULL DEFAULT 'draft'::character varying,
    created_at               timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at               timestamp with time zone    NOT NULL DEFAULT now(),
    driver_selfie_url        text,
    driver_selfie_expires_at timestamp with time zone,
    recurring_schedule_id    uuid,
    CONSTRAINT rides_pkey PRIMARY KEY (id),
    CONSTRAINT rides_available_seats_check CHECK (
        (available_seats >= 0) AND (available_seats <= 6)
    ),
    CONSTRAINT rides_price_per_seat_check CHECK (
        price_per_seat >= (0)::numeric
    ),
    CONSTRAINT rides_status_check CHECK (
        (status)::text = ANY (
            ARRAY[
                'draft'::character varying,
                'selfie_uploaded'::character varying,
                'active'::character varying,
                'completed'::character varying,
                'cancelled'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT rides_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id),
    CONSTRAINT rides_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
    CONSTRAINT rides_recurring_schedule_id_fkey FOREIGN KEY (recurring_schedule_id) REFERENCES public.recurring_schedules(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON public.rides USING btree (driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_vehicle_id ON public.rides USING btree (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_rides_search ON public.rides USING btree (from_location, to_location, journey_date);
CREATE INDEX IF NOT EXISTS idx_rides_status ON public.rides USING btree (status);
CREATE INDEX IF NOT EXISTS idx_rides_selfie_expiry ON public.rides USING btree (driver_selfie_expires_at);
CREATE INDEX IF NOT EXISTS idx_rides_recurring_schedule_id ON public.rides USING btree (recurring_schedule_id);

-- ---------------------------------------------------------------------------
-- Table: bookings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bookings (
    id               uuid                        NOT NULL DEFAULT gen_random_uuid(),
    ride_id          uuid                        NOT NULL,
    passenger_id     uuid                        NOT NULL,
    passenger_name   character varying(100)      NOT NULL,
    passenger_age    integer                     NOT NULL,
    passenger_gender character varying(20)       NOT NULL,
    payment_mode     character varying(20)       NOT NULL,
    status           character varying(20)       NOT NULL DEFAULT 'confirmed'::character varying,
    created_at       timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at       timestamp with time zone    NOT NULL DEFAULT now(),
    seats_booked     integer                     NOT NULL DEFAULT 1,
    total_amount     numeric(10,2)               NOT NULL DEFAULT 0.00,
    CONSTRAINT bookings_pkey PRIMARY KEY (id),
    CONSTRAINT bookings_passenger_age_check CHECK (passenger_age >= 18),
    CONSTRAINT bookings_passenger_gender_check CHECK (
        (passenger_gender)::text = ANY (
            ARRAY[
                'male'::character varying,
                'female'::character varying,
                'other'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT bookings_payment_mode_check CHECK (
        (payment_mode)::text = ANY (
            ARRAY[
                'cash'::character varying,
                'upi'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT bookings_seats_booked_check CHECK (
        (seats_booked >= 1) AND (seats_booked <= 6)
    ),
    CONSTRAINT bookings_status_check CHECK (
        (status)::text = ANY (
            ARRAY[
                'confirmed'::character varying,
                'cancelled'::character varying,
                'completed'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT bookings_total_amount_check CHECK (total_amount >= (0)::numeric),
    CONSTRAINT bookings_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id),
    CONSTRAINT bookings_passenger_id_fkey FOREIGN KEY (passenger_id) REFERENCES public.users(id)
);

CREATE INDEX IF NOT EXISTS idx_bookings_ride_id ON public.bookings USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_bookings_passenger_id ON public.bookings USING btree (passenger_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings USING btree (status);

-- ---------------------------------------------------------------------------
-- Table: booking_passengers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_passengers (
    id               uuid                        NOT NULL DEFAULT gen_random_uuid(),
    booking_id       uuid                        NOT NULL,
    passenger_number integer                     NOT NULL DEFAULT 1,
    passenger_name   character varying(100)      NOT NULL,
    passenger_age    integer                     NOT NULL,
    passenger_gender character varying(20)       NOT NULL,
    created_at       timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT booking_passengers_pkey PRIMARY KEY (id),
    CONSTRAINT booking_passengers_passenger_age_check CHECK (passenger_age >= 18),
    CONSTRAINT booking_passengers_passenger_gender_check CHECK (
        (passenger_gender)::text = ANY (
            ARRAY[
                'male'::character varying,
                'female'::character varying,
                'other'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT booking_passengers_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_booking_passengers_booking_id ON public.booking_passengers USING btree (booking_id);

-- ---------------------------------------------------------------------------
-- Table: otp_verifications
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.otp_verifications (
    id                     uuid                        NOT NULL DEFAULT gen_random_uuid(),
    identifier             character varying(255)      NOT NULL,
    otp_hash               text                        NOT NULL,
    purpose                character varying(20)       NOT NULL,
    expires_at             timestamp with time zone    NOT NULL,
    verified_at            timestamp with time zone,
    created_at             timestamp with time zone    NOT NULL DEFAULT now(),
    signup_data            jsonb,
    identifier_type        character varying(10)       NOT NULL,
    otp_code               character varying(10),
    resend_count           integer                     NOT NULL DEFAULT 0,
    next_resend_allowed_at timestamp with time zone,
    original_expires_at    timestamp with time zone    NOT NULL,
    failed_attempts        integer                     NOT NULL DEFAULT 0,
    locked_until           timestamp with time zone,
    CONSTRAINT otp_verifications_pkey PRIMARY KEY (id),
    CONSTRAINT otp_identifier_type_check CHECK (
        (identifier_type)::text = ANY (
            ARRAY[
                'phone'::character varying,
                'email'::character varying
            ]::text[]
        )
    ),
    CONSTRAINT otp_verifications_purpose_check CHECK (
        (purpose)::text = ANY (
            ARRAY[
                'login'::character varying,
                'signup'::character varying
            ]::text[]
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_otp_verifications_identifier ON public.otp_verifications USING btree (identifier);
CREATE INDEX IF NOT EXISTS idx_otp_verifications_expires_at ON public.otp_verifications USING btree (expires_at);
CREATE INDEX IF NOT EXISTS idx_otp_verifications_identifier_type ON public.otp_verifications USING btree (identifier_type);

-- ---------------------------------------------------------------------------
-- Table: user_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id                  uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id             uuid                        NOT NULL,
    session_token_hash  text                        NOT NULL,
    expires_at          timestamp with time zone    NOT NULL,
    created_at          timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT user_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT user_sessions_session_token_hash_key UNIQUE (session_token_hash),
    CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON public.user_sessions USING btree (expires_at);

-- ---------------------------------------------------------------------------
-- Table: notifications
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id         uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id    uuid                        NOT NULL,
    type       character varying(50)       NOT NULL,
    title      character varying(255)      NOT NULL,
    message    text                        NOT NULL,
    is_read    boolean                     NOT NULL DEFAULT false,
    created_at timestamp with time zone    DEFAULT CURRENT_TIMESTAMP,
    ride_id    uuid,
    booking_id uuid,
    CONSTRAINT notifications_pkey PRIMARY KEY (id),
    CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CONSTRAINT notifications_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL,
    CONSTRAINT notifications_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_notifications_ride_id ON public.notifications USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_notifications_booking_id ON public.notifications USING btree (booking_id);

-- ---------------------------------------------------------------------------
-- Sequence + Table: rate_limits
-- ---------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.rate_limits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE IF NOT EXISTS public.rate_limits (
    id            bigint                      NOT NULL DEFAULT nextval('public.rate_limits_id_seq'::regclass),
    rate_key      character varying(512)      NOT NULL,
    window_start  timestamp with time zone    NOT NULL DEFAULT now(),
    request_count integer                     NOT NULL DEFAULT 1,
    blocked_until timestamp with time zone,
    created_at    timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at    timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT rate_limits_pkey PRIMARY KEY (id)
);

ALTER SEQUENCE public.rate_limits_id_seq OWNED BY public.rate_limits.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limits_key ON public.rate_limits USING btree (rate_key);
CREATE INDEX IF NOT EXISTS idx_rate_limits_blocked ON public.rate_limits USING btree (blocked_until) WHERE (blocked_until IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON public.rate_limits USING btree (window_start);

-- =============================================================================
-- End of baseline migration
-- =============================================================================
