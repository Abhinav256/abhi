-- =============================================================================
-- AbhiShare — Complete Live Database Schema
-- =============================================================================
-- Source: Supabase Project "abhishare" (uqubmnnesyvvdeiwjnag)
-- Extracted: Live production/staging database
-- Usage: Run this script directly against any PostgreSQL 14+ / Supabase database.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. EXTENSIONS & SETTINGS
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- -----------------------------------------------------------------------------
-- 1. TABLES
-- -----------------------------------------------------------------------------

-- Table: users
CREATE TABLE IF NOT EXISTS public.users (
    id                      uuid                        NOT NULL,
    full_name               character varying(100)      NOT NULL,
    phone                   character varying(20)       NOT NULL,
    email                   character varying(255)      NOT NULL,
    date_of_birth           date                        NOT NULL,
    gender                  character varying(20)       NOT NULL,
    phone_verified_at       timestamp with time zone,
    email_verified_at       timestamp with time zone,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    pin_hash                character varying(255),
    nickname                character varying(255),
    pin_failed_attempts     integer                              DEFAULT 0,
    pin_locked_until        timestamp with time zone,
    pin_account_locked      boolean                              DEFAULT false,
    money_earned            numeric(10,2)               NOT NULL DEFAULT 0.00,
    referral_code           character varying(30),
    referred_by_id          uuid,
    referred_by_code        character varying(30),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_phone_key UNIQUE (phone),
    CONSTRAINT users_email_key UNIQUE (email),
    CONSTRAINT users_referral_code_key UNIQUE (referral_code),
    CONSTRAINT users_gender_check CHECK (
        (gender)::text = ANY (ARRAY[
            ('male'::character varying)::text,
            ('female'::character varying)::text,
            ('other'::character varying)::text
        ])
    )
);

-- Table: user_sessions
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    session_token_hash      text                        NOT NULL,
    expires_at              timestamp with time zone    NOT NULL,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT user_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT user_sessions_session_token_hash_key UNIQUE (session_token_hash)
);

-- Table: otp_verifications
CREATE TABLE IF NOT EXISTS public.otp_verifications (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    identifier              character varying(255)      NOT NULL,
    otp_hash                text                        NOT NULL,
    purpose                 character varying(20)       NOT NULL,
    expires_at              timestamp with time zone    NOT NULL,
    verified_at             timestamp with time zone,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    signup_data             jsonb,
    identifier_type         character varying(10)       NOT NULL,
    otp_code                character varying(10),
    resend_count            integer                     NOT NULL DEFAULT 0,
    next_resend_allowed_at  timestamp with time zone,
    original_expires_at     timestamp with time zone    NOT NULL,
    failed_attempts         integer                     NOT NULL DEFAULT 0,
    locked_until            timestamp with time zone,
    CONSTRAINT otp_verifications_pkey PRIMARY KEY (id),
    CONSTRAINT otp_identifier_type_check CHECK (
        (identifier_type)::text = ANY (ARRAY[
            ('phone'::character varying)::text,
            ('email'::character varying)::text
        ])
    ),
    CONSTRAINT otp_verifications_purpose_check CHECK (
        (purpose)::text = ANY (ARRAY[
            ('login'::character varying)::text,
            ('signup'::character varying)::text
        ])
    )
);

-- Table: vehicles
CREATE TABLE IF NOT EXISTS public.vehicles (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    vehicle_number          character varying(50)       NOT NULL,
    vehicle_type            character varying(20)       NOT NULL,
    model                   character varying(100)      NOT NULL,
    rc_photo_url            text,
    vehicle_photo_url       text,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT vehicles_pkey PRIMARY KEY (id),
    CONSTRAINT vehicles_vehicle_number_key UNIQUE (vehicle_number),
    CONSTRAINT vehicles_vehicle_type_check CHECK (
        (vehicle_type)::text = ANY (ARRAY[
            ('two_wheeler'::character varying)::text,
            ('five_seater'::character varying)::text,
            ('seven_seater'::character varying)::text
        ])
    )
);

-- Table: saved_locations
CREATE TABLE IF NOT EXISTS public.saved_locations (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    name                    character varying(255)      NOT NULL,
    address                 text                        NOT NULL,
    created_at              timestamp with time zone             DEFAULT now(),
    updated_at              timestamp with time zone             DEFAULT now(),
    CONSTRAINT saved_locations_pkey PRIMARY KEY (id)
);

-- Table: recurring_schedules
CREATE TABLE IF NOT EXISTS public.recurring_schedules (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    recurrence_type         character varying(30)       NOT NULL,
    selected_weekdays       text[]                               DEFAULT '{}'::text[],
    start_date              date                        NOT NULL,
    end_date                date,
    occurrence_count        integer,
    ride_template           jsonb                       NOT NULL,
    status                  character varying(20)       NOT NULL DEFAULT 'active'::character varying,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT recurring_schedules_pkey PRIMARY KEY (id),
    CONSTRAINT recurring_schedules_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('draft'::character varying)::text,
            ('active'::character varying)::text,
            ('paused'::character varying)::text,
            ('cancelled'::character varying)::text
        ])
    )
);

-- Table: rides
CREATE TABLE IF NOT EXISTS public.rides (
    id                          uuid                        NOT NULL DEFAULT gen_random_uuid(),
    driver_id                   uuid                        NOT NULL,
    vehicle_id                  uuid                        NOT NULL,
    from_location               character varying(150)      NOT NULL,
    to_location                 character varying(150)      NOT NULL,
    journey_date                date                        NOT NULL,
    departure_time              time without time zone      NOT NULL,
    estimated_arrival_time      time without time zone      NOT NULL,
    available_seats             integer                     NOT NULL,
    price_per_seat              numeric(10,2)               NOT NULL,
    status                      character varying(20)       NOT NULL DEFAULT 'draft'::character varying,
    created_at                  timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at                  timestamp with time zone    NOT NULL DEFAULT now(),
    driver_selfie_url           text,
    driver_selfie_expires_at    timestamp with time zone,
    recurring_schedule_id       uuid,
    is_women_only               boolean                     NOT NULL DEFAULT false,
    user_amount                 numeric(10,2)               NOT NULL DEFAULT 0.00,
    app_amount                  numeric(10,2)               NOT NULL DEFAULT 0.00,
    total_amount                numeric(10,2)               NOT NULL DEFAULT 0.00,
    settlement_status           character varying(20)       NOT NULL DEFAULT 'unsettled'::character varying,
    completed_at                timestamp with time zone,
    pickup_latitude             double precision,
    pickup_longitude            double precision,
    destination_latitude        double precision,
    destination_longitude       double precision,
    route_geometry              jsonb,
    route_distance              double precision,
    route_duration              double precision,
    route_summary               text,
    route_waypoints             jsonb,
    CONSTRAINT rides_pkey PRIMARY KEY (id),
    CONSTRAINT rides_app_amount_check CHECK (app_amount >= (0)::numeric),
    CONSTRAINT rides_user_amount_check CHECK (user_amount >= (0)::numeric),
    CONSTRAINT rides_total_amount_check CHECK (total_amount >= (0)::numeric),
    CONSTRAINT rides_price_per_seat_check CHECK (price_per_seat >= (0)::numeric),
    CONSTRAINT rides_available_seats_check CHECK ((available_seats >= 0) AND (available_seats <= 6)),
    CONSTRAINT rides_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('draft'::character varying)::text,
            ('selfie_uploaded'::character varying)::text,
            ('active'::character varying)::text,
            ('completed'::character varying)::text,
            ('cancelled'::character varying)::text
        ])
    )
);

-- Table: bookings
CREATE TABLE IF NOT EXISTS public.bookings (
    id                              uuid                        NOT NULL DEFAULT gen_random_uuid(),
    ride_id                         uuid                        NOT NULL,
    passenger_id                    uuid                        NOT NULL,
    passenger_name                  character varying(100)      NOT NULL,
    passenger_age                   integer                     NOT NULL,
    passenger_gender                character varying(20)       NOT NULL,
    payment_mode                    character varying(20)       NOT NULL,
    status                          character varying(20)       NOT NULL DEFAULT 'confirmed'::character varying,
    created_at                      timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at                      timestamp with time zone    NOT NULL DEFAULT now(),
    seats_booked                    integer                     NOT NULL DEFAULT 1,
    total_amount                    numeric(10,2)               NOT NULL DEFAULT 0.00,
    settlement_status               character varying(20)       NOT NULL DEFAULT 'unsettled'::character varying,
    driver_earnings                 numeric(10,2)               NOT NULL DEFAULT 0.00,
    platform_charge                 numeric(10,2)               NOT NULL DEFAULT 0.00,
    from_location                   character varying(255),
    to_location                     character varying(255),
    pickup_latitude                 double precision,
    pickup_longitude                double precision,
    destination_latitude            double precision,
    destination_longitude           double precision,
    pickup_distance_along_route     double precision,
    drop_distance_along_route       double precision,
    CONSTRAINT bookings_pkey PRIMARY KEY (id),
    CONSTRAINT bookings_passenger_age_check CHECK (passenger_age >= 18),
    CONSTRAINT bookings_seats_booked_check CHECK ((seats_booked >= 1) AND (seats_booked <= 6)),
    CONSTRAINT bookings_total_amount_check CHECK (total_amount >= (0)::numeric),
    CONSTRAINT bookings_passenger_gender_check CHECK (
        (passenger_gender)::text = ANY (ARRAY[
            ('male'::character varying)::text,
            ('female'::character varying)::text,
            ('other'::character varying)::text
        ])
    ),
    CONSTRAINT bookings_payment_mode_check CHECK (
        (payment_mode)::text = ANY (ARRAY[
            ('cash'::character varying)::text,
            ('upi'::character varying)::text
        ])
    ),
    CONSTRAINT bookings_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('confirmed'::character varying)::text,
            ('cancelled'::character varying)::text,
            ('completed'::character varying)::text
        ])
    )
);

-- Table: booking_passengers
CREATE TABLE IF NOT EXISTS public.booking_passengers (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    booking_id              uuid                        NOT NULL,
    passenger_number        integer                     NOT NULL DEFAULT 1,
    passenger_name          character varying(100)      NOT NULL,
    passenger_age           integer                     NOT NULL,
    passenger_gender        character varying(20)       NOT NULL,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    passenger_phone         character varying(20),
    CONSTRAINT booking_passengers_pkey PRIMARY KEY (id),
    CONSTRAINT booking_passengers_passenger_age_check CHECK (passenger_age >= 18),
    CONSTRAINT booking_passengers_passenger_gender_check CHECK (
        (passenger_gender)::text = ANY (ARRAY[
            ('male'::character varying)::text,
            ('female'::character varying)::text,
            ('other'::character varying)::text
        ])
    )
);

-- Table: ratings
CREATE TABLE IF NOT EXISTS public.ratings (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    ride_id                 uuid                        NOT NULL,
    rater_id                uuid                        NOT NULL,
    ratee_id                uuid                        NOT NULL,
    rating_value            integer                     NOT NULL,
    feedback                text,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT ratings_pkey PRIMARY KEY (id),
    CONSTRAINT unique_ride_rater_ratee UNIQUE (ride_id, rater_id, ratee_id),
    CONSTRAINT ratings_rating_value_check CHECK ((rating_value >= 1) AND (rating_value <= 5))
);

-- Table: notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    type                    character varying(50)       NOT NULL,
    title                   character varying(255)      NOT NULL,
    message                 text                        NOT NULL,
    is_read                 boolean                     NOT NULL DEFAULT false,
    created_at              timestamp with time zone             DEFAULT CURRENT_TIMESTAMP,
    ride_id                 uuid,
    booking_id              uuid,
    push_sent               boolean                              DEFAULT false,
    CONSTRAINT notifications_pkey PRIMARY KEY (id)
);

-- Table: rate_limits
CREATE TABLE IF NOT EXISTS public.rate_limits (
    id                      bigint                      GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    rate_key                character varying(512)      NOT NULL,
    window_start            timestamp with time zone    NOT NULL DEFAULT now(),
    request_count           integer                     NOT NULL DEFAULT 1,
    blocked_until           timestamp with time zone,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now()
);

-- Table: wallets
CREATE TABLE IF NOT EXISTS public.wallets (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    balance                 numeric(12,2)               NOT NULL DEFAULT 0.00,
    currency                character varying(3)        NOT NULL DEFAULT 'INR'::character varying,
    is_locked               boolean                     NOT NULL DEFAULT false,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT wallets_pkey PRIMARY KEY (id),
    CONSTRAINT wallets_user_id_key UNIQUE (user_id)
);

-- Table: wallet_transactions
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    wallet_id               uuid                        NOT NULL,
    user_id                 uuid                        NOT NULL,
    reference_id            character varying(100)      NOT NULL,
    type                    character varying(30)       NOT NULL,
    status                  character varying(20)       NOT NULL DEFAULT 'completed'::character varying,
    amount                  numeric(12,2)               NOT NULL,
    opening_balance         numeric(12,2)               NOT NULL DEFAULT 0.00,
    closing_balance         numeric(12,2)               NOT NULL DEFAULT 0.00,
    title                   character varying(100)      NOT NULL,
    subtitle                character varying(255)      NOT NULL,
    category                character varying(50)       NOT NULL DEFAULT 'General'::character varying,
    payment_method          character varying(100)      NOT NULL,
    payment_method_type     character varying(50)       NOT NULL DEFAULT 'other'::character varying,
    destination_info        text,
    failure_reason          text,
    metadata                jsonb                                DEFAULT '{}'::jsonb,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id),
    CONSTRAINT wallet_transactions_reference_id_key UNIQUE (reference_id),
    CONSTRAINT wallet_transactions_amount_check CHECK (amount > (0)::numeric),
    CONSTRAINT wallet_transactions_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('completed'::character varying)::text,
            ('pending'::character varying)::text,
            ('failed'::character varying)::text
        ])
    ),
    CONSTRAINT wallet_transactions_type_check CHECK (
        (type)::text = ANY (ARRAY[
            ('money_added'::character varying)::text,
            ('withdrawal'::character varying)::text,
            ('ride_payment'::character varying)::text,
            ('refund'::character varying)::text,
            ('referral_reward'::character varying)::text,
            ('ride_earnings_upi'::character varying)::text,
            ('platform_charge_cash'::character varying)::text
        ])
    )
);

-- Table: saved_bank_accounts
CREATE TABLE IF NOT EXISTS public.saved_bank_accounts (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    account_holder_name     character varying(100)      NOT NULL,
    account_number          character varying(50)       NOT NULL,
    ifsc_code               character varying(20)       NOT NULL,
    bank_name               character varying(100)      NOT NULL,
    branch                  character varying(100),
    is_primary              boolean                     NOT NULL DEFAULT false,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT saved_bank_accounts_pkey PRIMARY KEY (id)
);

-- Table: saved_upi_ids
CREATE TABLE IF NOT EXISTS public.saved_upi_ids (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    upi_id                  character varying(100)      NOT NULL,
    label                   character varying(100)      NOT NULL DEFAULT 'UPI'::character varying,
    is_primary              boolean                     NOT NULL DEFAULT false,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT saved_upi_ids_pkey PRIMARY KEY (id)
);

-- Table: saved_cards
CREATE TABLE IF NOT EXISTS public.saved_cards (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    last_four_digits        character varying(4)        NOT NULL,
    card_holder_name        character varying(100)      NOT NULL,
    expiry_date             character varying(10)       NOT NULL,
    card_network            character varying(30)       NOT NULL,
    is_credit               boolean                     NOT NULL DEFAULT false,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT saved_cards_pkey PRIMARY KEY (id)
);

-- Table: payment_orders
CREATE TABLE IF NOT EXISTS public.payment_orders (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    order_id                character varying(100)      NOT NULL,
    amount                  numeric(10,2)               NOT NULL,
    currency                character varying(10)       NOT NULL DEFAULT 'INR'::character varying,
    purpose                 character varying(50)       NOT NULL,
    status                  character varying(30)       NOT NULL DEFAULT 'created'::character varying,
    payment_id              character varying(100),
    signature               text,
    metadata                jsonb                                DEFAULT '{}'::jsonb,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT payment_orders_pkey PRIMARY KEY (id),
    CONSTRAINT payment_orders_order_id_key UNIQUE (order_id),
    CONSTRAINT chk_payment_orders_purpose CHECK (
        (purpose)::text = ANY (ARRAY[
            ('ride_booking'::character varying)::text,
            ('wallet_topup'::character varying)::text
        ])
    ),
    CONSTRAINT chk_payment_orders_status CHECK (
        (status)::text = ANY (ARRAY[
            ('created'::character varying)::text,
            ('paid'::character varying)::text,
            ('failed'::character varying)::text,
            ('cancelled'::character varying)::text
        ])
    )
);

-- Table: referrals
CREATE TABLE IF NOT EXISTS public.referrals (
    id                          uuid                        NOT NULL DEFAULT gen_random_uuid(),
    referrer_id                 uuid                        NOT NULL,
    referee_id                  uuid                        NOT NULL,
    referral_code               character varying(50)       NOT NULL,
    status                      character varying(30)       NOT NULL DEFAULT 'registered'::character varying,
    reward_amount               numeric(10,2)               NOT NULL DEFAULT 50.00,
    referrer_ride_completed     boolean                     NOT NULL DEFAULT false,
    referee_ride_completed      boolean                     NOT NULL DEFAULT false,
    reward_credited_at          timestamp with time zone,
    reward_transaction_id       uuid,
    created_at                  timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at                  timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT referrals_pkey PRIMARY KEY (id),
    CONSTRAINT referrals_referee_id_key UNIQUE (referee_id),
    CONSTRAINT chk_no_self_referral CHECK (referrer_id <> referee_id),
    CONSTRAINT referrals_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('registered'::character varying)::text,
            ('ride_pending'::character varying)::text,
            ('eligible'::character varying)::text,
            ('reward_credited'::character varying)::text
        ])
    )
);

-- Table: chat_conversations
CREATE TABLE IF NOT EXISTS public.chat_conversations (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    ride_id                 uuid                        NOT NULL,
    booking_id              uuid                        NOT NULL,
    driver_id               uuid                        NOT NULL,
    passenger_id            uuid                        NOT NULL,
    status                  character varying(20)       NOT NULL DEFAULT 'active'::character varying,
    last_message_at         timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at              timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_protected            boolean                     NOT NULL DEFAULT false,
    protection_reason       text,
    protected_at            timestamp with time zone,
    CONSTRAINT chat_conversations_pkey PRIMARY KEY (id),
    CONSTRAINT uq_chat_conversations_booking UNIQUE (booking_id),
    CONSTRAINT chk_chat_participants_distinct CHECK (driver_id <> passenger_id),
    CONSTRAINT chat_conversations_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('active'::character varying)::text,
            ('archived'::character varying)::text,
            ('read_only'::character varying)::text,
            ('completed'::character varying)::text
        ])
    )
);

-- Table: chat_messages
CREATE TABLE IF NOT EXISTS public.chat_messages (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    conversation_id         uuid                        NOT NULL,
    sender_id               uuid,
    sender_role             character varying(20)       NOT NULL,
    message_type            character varying(20)       NOT NULL DEFAULT 'text'::character varying,
    content                 text                        NOT NULL,
    client_message_id       character varying(100),
    is_read                 boolean                     NOT NULL DEFAULT false,
    read_at                 timestamp with time zone,
    created_at              timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chat_messages_pkey PRIMARY KEY (id),
    CONSTRAINT chat_messages_sender_role_check CHECK (
        (sender_role)::text = ANY (ARRAY[
            ('driver'::character varying)::text,
            ('passenger'::character varying)::text,
            ('system'::character varying)::text
        ])
    ),
    CONSTRAINT chat_messages_message_type_check CHECK (
        (message_type)::text = ANY (ARRAY[
            ('text'::character varying)::text,
            ('system'::character varying)::text,
            ('quick_reply'::character varying)::text,
            ('location'::character varying)::text
        ])
    )
);

-- Table: user_blocks
CREATE TABLE IF NOT EXISTS public.user_blocks (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    blocker_id              uuid                        NOT NULL,
    blocked_id              uuid                        NOT NULL,
    reason                  text,
    created_at              timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT user_blocks_pkey PRIMARY KEY (id),
    CONSTRAINT uq_user_blocks UNIQUE (blocker_id, blocked_id),
    CONSTRAINT chk_user_blocks_distinct CHECK (blocker_id <> blocked_id)
);

-- Table: user_reports
CREATE TABLE IF NOT EXISTS public.user_reports (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    reporter_id             uuid                        NOT NULL,
    reported_id             uuid                        NOT NULL,
    ride_id                 uuid,
    conversation_id         uuid,
    reason                  character varying(100)      NOT NULL,
    description             text,
    status                  character varying(20)       NOT NULL DEFAULT 'pending'::character varying,
    created_at              timestamp with time zone    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT user_reports_pkey PRIMARY KEY (id),
    CONSTRAINT chk_user_reports_distinct CHECK (reporter_id <> reported_id),
    CONSTRAINT user_reports_status_check CHECK (
        (status)::text = ANY (ARRAY[
            ('pending'::character varying)::text,
            ('reviewed'::character varying)::text,
            ('dismissed'::character varying)::text,
            ('actioned'::character varying)::text
        ])
    )
);

-- Table: user_device_tokens
CREATE TABLE IF NOT EXISTS public.user_device_tokens (
    id                      uuid                        NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid                        NOT NULL,
    device_token            text                        NOT NULL,
    platform                text                        NOT NULL DEFAULT 'android'::text,
    voip_token              text,
    created_at              timestamp with time zone    NOT NULL DEFAULT now(),
    updated_at              timestamp with time zone    NOT NULL DEFAULT now(),
    CONSTRAINT user_device_tokens_pkey PRIMARY KEY (id),
    CONSTRAINT uq_user_device UNIQUE (user_id, device_token)
);

-- -----------------------------------------------------------------------------
-- 2. FOREIGN KEY CONSTRAINTS
-- -----------------------------------------------------------------------------

-- users
ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_referred_by_id_fkey FOREIGN KEY (referred_by_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- user_sessions
ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- vehicles
ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

-- saved_locations
ALTER TABLE ONLY public.saved_locations
    ADD CONSTRAINT saved_locations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- recurring_schedules
ALTER TABLE ONLY public.recurring_schedules
    ADD CONSTRAINT recurring_schedules_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- rides
ALTER TABLE ONLY public.rides
    ADD CONSTRAINT rides_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id),
    ADD CONSTRAINT rides_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE,
    ADD CONSTRAINT rides_recurring_schedule_id_fkey FOREIGN KEY (recurring_schedule_id) REFERENCES public.recurring_schedules(id) ON DELETE SET NULL;

-- bookings
ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_passenger_id_fkey FOREIGN KEY (passenger_id) REFERENCES public.users(id),
    ADD CONSTRAINT bookings_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id);

-- booking_passengers
ALTER TABLE ONLY public.booking_passengers
    ADD CONSTRAINT booking_passengers_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;

-- ratings
ALTER TABLE ONLY public.ratings
    ADD CONSTRAINT ratings_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE,
    ADD CONSTRAINT ratings_rater_id_fkey FOREIGN KEY (rater_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT ratings_ratee_id_fkey FOREIGN KEY (ratee_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- notifications
ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT notifications_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;

-- wallets
ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- wallet_transactions
ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE CASCADE,
    ADD CONSTRAINT wallet_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- saved_bank_accounts
ALTER TABLE ONLY public.saved_bank_accounts
    ADD CONSTRAINT saved_bank_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- saved_upi_ids
ALTER TABLE ONLY public.saved_upi_ids
    ADD CONSTRAINT saved_upi_ids_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- saved_cards
ALTER TABLE ONLY public.saved_cards
    ADD CONSTRAINT saved_cards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- payment_orders
ALTER TABLE ONLY public.payment_orders
    ADD CONSTRAINT payment_orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- referrals
ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referrer_id_fkey FOREIGN KEY (referrer_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT referrals_referee_id_fkey FOREIGN KEY (referee_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT referrals_reward_transaction_id_fkey FOREIGN KEY (reward_transaction_id) REFERENCES public.wallet_transactions(id) ON DELETE SET NULL;

-- chat_conversations
ALTER TABLE ONLY public.chat_conversations
    ADD CONSTRAINT chat_conversations_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE,
    ADD CONSTRAINT chat_conversations_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE,
    ADD CONSTRAINT chat_conversations_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT chat_conversations_passenger_id_fkey FOREIGN KEY (passenger_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- chat_messages
ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    ADD CONSTRAINT chat_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- user_blocks
ALTER TABLE ONLY public.user_blocks
    ADD CONSTRAINT user_blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT user_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- user_reports
ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT user_reports_reported_id_fkey FOREIGN KEY (reported_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT user_reports_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL,
    ADD CONSTRAINT user_reports_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.chat_conversations(id) ON DELETE SET NULL;

-- user_device_tokens
ALTER TABLE ONLY public.user_device_tokens
    ADD CONSTRAINT user_device_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------------
-- 3. INDEXES
-- -----------------------------------------------------------------------------

-- users
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON public.users USING btree (referral_code);

-- user_sessions
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON public.user_sessions USING btree (expires_at);

-- otp_verifications
CREATE INDEX IF NOT EXISTS idx_otp_verifications_identifier ON public.otp_verifications USING btree (identifier);
CREATE INDEX IF NOT EXISTS idx_otp_verifications_identifier_type ON public.otp_verifications USING btree (identifier_type);
CREATE INDEX IF NOT EXISTS idx_otp_verifications_expires_at ON public.otp_verifications USING btree (expires_at);

-- recurring_schedules
CREATE INDEX IF NOT EXISTS idx_recurring_schedules_user_id ON public.recurring_schedules USING btree (user_id);

-- rides
CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON public.rides USING btree (driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_vehicle_id ON public.rides USING btree (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_rides_recurring_schedule_id ON public.rides USING btree (recurring_schedule_id);
CREATE INDEX IF NOT EXISTS idx_rides_status ON public.rides USING btree (status);
CREATE INDEX IF NOT EXISTS idx_rides_is_women_only ON public.rides USING btree (is_women_only);
CREATE INDEX IF NOT EXISTS idx_rides_search ON public.rides USING btree (from_location, to_location, journey_date);
CREATE INDEX IF NOT EXISTS idx_rides_status_journey_date ON public.rides USING btree (status, journey_date);
CREATE INDEX IF NOT EXISTS idx_rides_driver_settle ON public.rides USING btree (driver_id, status);
CREATE INDEX IF NOT EXISTS idx_rides_completed_at ON public.rides USING btree (status, completed_at);
CREATE INDEX IF NOT EXISTS idx_rides_selfie_expiry ON public.rides USING btree (driver_selfie_expires_at);

-- bookings
CREATE INDEX IF NOT EXISTS idx_bookings_ride_id ON public.bookings USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_bookings_passenger_id ON public.bookings USING btree (passenger_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings USING btree (status);
CREATE INDEX IF NOT EXISTS idx_bookings_ride_settle ON public.bookings USING btree (ride_id, settlement_status);

-- booking_passengers
CREATE INDEX IF NOT EXISTS idx_booking_passengers_booking_id ON public.booking_passengers USING btree (booking_id);

-- ratings
CREATE INDEX IF NOT EXISTS idx_ratings_ride_id ON public.ratings USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rater_id ON public.ratings USING btree (rater_id);
CREATE INDEX IF NOT EXISTS idx_ratings_ratee_id ON public.ratings USING btree (ratee_id);

-- notifications
CREATE INDEX IF NOT EXISTS idx_notifications_ride_id ON public.notifications USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_notifications_booking_id ON public.notifications USING btree (booking_id);
CREATE INDEX IF NOT EXISTS idx_notifications_push_sent ON public.notifications USING btree (push_sent) WHERE (push_sent = false);

-- rate_limits
CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON public.rate_limits USING btree (window_start);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limits_key ON public.rate_limits USING btree (rate_key);
CREATE INDEX IF NOT EXISTS idx_rate_limits_blocked ON public.rate_limits USING btree (blocked_until) WHERE (blocked_until IS NOT NULL);

-- wallets
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets USING btree (user_id);

-- wallet_transactions
CREATE INDEX IF NOT EXISTS idx_wallet_txns_wallet_id ON public.wallet_transactions USING btree (wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_txns_user_id ON public.wallet_transactions USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_txns_created_at ON public.wallet_transactions USING btree (created_at DESC);

-- saved_bank_accounts
CREATE INDEX IF NOT EXISTS idx_saved_bank_accounts_user_id ON public.saved_bank_accounts USING btree (user_id);

-- saved_upi_ids
CREATE INDEX IF NOT EXISTS idx_saved_upi_ids_user_id ON public.saved_upi_ids USING btree (user_id);

-- saved_cards
CREATE INDEX IF NOT EXISTS idx_saved_cards_user_id ON public.saved_cards USING btree (user_id);

-- payment_orders
CREATE INDEX IF NOT EXISTS idx_payment_orders_user_id ON public.payment_orders USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_order_id ON public.payment_orders USING btree (order_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_payment_id ON public.payment_orders USING btree (payment_id);

-- referrals
CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON public.referrals USING btree (referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referee_id ON public.referrals USING btree (referee_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals USING btree (status);
CREATE INDEX IF NOT EXISTS idx_referrals_daily_ist ON public.referrals USING btree (referrer_id, (((created_at AT TIME ZONE 'Asia/Kolkata'::text))::date));

-- chat_conversations
CREATE INDEX IF NOT EXISTS idx_chat_conv_ride ON public.chat_conversations USING btree (ride_id);
CREATE INDEX IF NOT EXISTS idx_chat_conv_driver ON public.chat_conversations USING btree (driver_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conv_passenger ON public.chat_conversations USING btree (passenger_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_cleanup ON public.chat_conversations USING btree (status, is_protected, ride_id);

-- chat_messages
CREATE INDEX IF NOT EXISTS idx_chat_msgs_conv_created ON public.chat_messages USING btree (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_msgs_conv_unread ON public.chat_messages USING btree (conversation_id, is_read) WHERE (is_read = false);
CREATE INDEX IF NOT EXISTS idx_chat_msgs_client_id ON public.chat_messages USING btree (conversation_id, client_message_id) WHERE (client_message_id IS NOT NULL);

-- user_blocks
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON public.user_blocks USING btree (blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks USING btree (blocked_id);

-- user_reports
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON public.user_reports USING btree (reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON public.user_reports USING btree (reported_id);

-- user_device_tokens
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user ON public.user_device_tokens USING btree (user_id);

-- -----------------------------------------------------------------------------
-- 4. FUNCTIONS
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_women_only_ride_driver()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    driver_gender character varying(20);
BEGIN
    IF NEW.is_women_only = true THEN
        SELECT gender INTO driver_gender FROM public.users WHERE id = NEW.driver_id;
        IF driver_gender IS NULL OR driver_gender <> 'female' THEN
            RAISE EXCEPTION 'Only verified female drivers can create Women Only rides';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_women_only_passenger()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    ride_women_only boolean;
BEGIN
    SELECT r.is_women_only INTO ride_women_only
    FROM public.bookings b
    JOIN public.rides r ON r.id = b.ride_id
    WHERE b.id = NEW.booking_id;

    IF ride_women_only = true THEN
        IF LOWER(TRIM(NEW.passenger_gender)) <> 'female' THEN
            RAISE EXCEPTION 'Only female passengers can travel on Women Only rides';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_conversations()
RETURNS TABLE(deleted_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    count_deleted INT;
BEGIN
    -- 1. Protect any conversations involving reports or blocks before cleanup
    UPDATE chat_conversations c
    SET is_protected = TRUE,
        protection_reason = CASE
            WHEN EXISTS (
                SELECT 1 FROM user_reports ur 
                WHERE ur.conversation_id = c.id 
                   OR ur.ride_id = c.ride_id 
                   OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id) 
                   OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
            ) AND EXISTS (
                SELECT 1 FROM user_blocks ub 
                WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id) 
                   OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
            ) THEN 'reported_and_blocked'
            WHEN EXISTS (
                SELECT 1 FROM user_reports ur 
                WHERE ur.conversation_id = c.id 
                   OR ur.ride_id = c.ride_id 
                   OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id) 
                   OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
            ) THEN 'reported'
            ELSE 'blocked'
        END,
        protected_at = COALESCE(protected_at, NOW()),
        updated_at = NOW()
    WHERE c.is_protected = FALSE
      AND (
          EXISTS (
              SELECT 1 FROM user_reports ur
              WHERE ur.conversation_id = c.id
                 OR ur.ride_id = c.ride_id
                 OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id)
                 OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
          )
          OR EXISTS (
              SELECT 1 FROM user_blocks ub
              WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id)
                 OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
          )
      );

    -- 2. Delete conversations and messages for completed rides where completion timestamp > 7 days ago,
    --    and not protected by reports, blocks, or manual hold.
    WITH to_delete AS (
        SELECT c.id
        FROM chat_conversations c
        JOIN rides r ON r.id = c.ride_id
        WHERE r.status = 'completed'
          AND r.completed_at IS NOT NULL
          AND r.completed_at < NOW() - INTERVAL '7 days'
          AND c.is_protected = FALSE
          AND NOT EXISTS (
              SELECT 1 FROM user_reports ur
              WHERE ur.conversation_id = c.id
                 OR ur.ride_id = c.ride_id
                 OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id)
                 OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
          )
          AND NOT EXISTS (
              SELECT 1 FROM user_blocks ub
              WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id)
                 OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
          )
        FOR UPDATE OF c SKIP LOCKED
    ),
    deleted AS (
        DELETE FROM chat_conversations
        WHERE id IN (SELECT id FROM to_delete)
        RETURNING id
    )
    SELECT COUNT(*)::INT INTO count_deleted FROM deleted;

    RETURN QUERY SELECT count_deleted;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. TRIGGERS
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_check_women_only_ride_driver ON public.rides;
CREATE TRIGGER trg_check_women_only_ride_driver
    BEFORE INSERT OR UPDATE OF is_women_only, driver_id
    ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.check_women_only_ride_driver();

DROP TRIGGER IF EXISTS trg_check_women_only_passenger ON public.booking_passengers;
CREATE TRIGGER trg_check_women_only_passenger
    BEFORE INSERT OR UPDATE
    ON public.booking_passengers
    FOR EACH ROW
    EXECUTE FUNCTION public.check_women_only_passenger();

-- =============================================================================
-- End of AbhiShare Schema Extraction
-- =============================================================================
