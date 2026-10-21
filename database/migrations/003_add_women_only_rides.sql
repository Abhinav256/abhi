-- =============================================================================
-- AbhiShare — Migration: Add Women Only Ride Feature
-- =============================================================================
-- Migration : 003_add_women_only_rides.sql
-- Created   : 2026-10-11
-- Purpose   : Adds is_women_only column to rides table with index,
--             adds passenger_phone column to booking_passengers for identity verification,
--             and creates triggers to enforce that only verified female drivers can
--             create Women Only rides and only verified female passengers can book them.
-- =============================================================================

-- Step 1: Add is_women_only to rides table
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS is_women_only boolean NOT NULL DEFAULT false;

-- Step 2: Index on is_women_only for fast search filtering
CREATE INDEX IF NOT EXISTS idx_rides_is_women_only ON public.rides (is_women_only);

-- Step 3: Add passenger_phone to booking_passengers for passenger-level verification
ALTER TABLE public.booking_passengers 
ADD COLUMN IF NOT EXISTS passenger_phone character varying(20);

-- Step 4: Database trigger to ensure only female drivers can create Women Only rides
CREATE OR REPLACE FUNCTION public.check_women_only_ride_driver()
RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql;

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_check_women_only_ride_driver') THEN 
        CREATE TRIGGER trg_check_women_only_ride_driver 
        BEFORE INSERT OR UPDATE OF is_women_only, driver_id 
        ON public.rides 
        FOR EACH ROW 
        EXECUTE FUNCTION public.check_women_only_ride_driver(); 
    END IF; 
END $$;

-- Step 5: Database trigger to validate passengers on Women Only rides
CREATE OR REPLACE FUNCTION public.check_women_only_passenger()
RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql;

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_check_women_only_passenger') THEN 
        CREATE TRIGGER trg_check_women_only_passenger 
        BEFORE INSERT OR UPDATE 
        ON public.booking_passengers 
        FOR EACH ROW 
        EXECUTE FUNCTION public.check_women_only_passenger(); 
    END IF; 
END $$;
