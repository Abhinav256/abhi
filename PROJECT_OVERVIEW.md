# AbhiShare — Project Overview

## Purpose

AbhiShare is a planned-journey vehicle and seat-sharing platform. Drivers publish trips they already intend to make and offer spare seats; passengers find compatible trips and reserve seats. It is closer to a carpooling marketplace than an on-demand taxi product.

The primary journey is: driver adds a vehicle → creates and publishes a ride → passenger searches → passenger books seats → trip completes → participants rate each other.

A single account can be both a driver and a passenger. A ride belongs to its driver; one ride can have multiple passenger bookings.

## Product Scope

### Implemented backend capabilities

- OTP-based account creation and sign-in through phone or email, plus a unified authentication flow.
- Bearer-token sessions, profile retrieval and update, logout, and optional passcode/PIN management.
- Vehicle creation, listing, detail retrieval, deletion, and image upload.
- Ride drafting, selfie upload, publication, search, detail lookup, completion, cancellation, and draft deletion.
- Booking creation, driver/passenger booking views, booking detail, and passenger cancellation.
- Saved locations, in-app notifications, recurring ride schedules, and ratings.
- Database-backed rate limiting for authentication and authenticated endpoints.

### Client applications

- **mobile/** — Flutter app with auth, profile/security, vehicles, ride creation/search/detail, bookings, saved locations, notifications, recurring schedules, and ratings.
- **customer-web/** — React/Vite customer web application scaffold.
- **admin-web/** — React/Vite admin application scaffold.

The web projects currently appear starter-level when compared with the mobile and backend implementations.

## Architecture

```text
Flutter mobile app       React customer/admin web apps
          │                         │
          └──────── REST/JSON ──────┘
                         │
                    Go + Fiber API
                         │
           PostgreSQL / Supabase PostgreSQL
                         │
           Supabase object storage or local uploads
```

The Go application follows a handler → service → database/storage layout. PostgreSQL is the system of record. File storage uses a provider abstraction with Supabase and local implementations.

## Technology Specifications

| Area | Technologies in the repository |
| --- | --- |
| API | Go, Fiber v2, REST/JSON, pgx connection pool |
| Database | PostgreSQL; schema and migrations in database/ |
| Storage | Supabase Storage or local filesystem |
| Authentication | Email/phone OTP, hashed sessions, bearer tokens, Argon2 PIN support |
| Email | SMTP with STARTTLS configuration |
| Mobile | Flutter/Dart; http, shared_preferences, flutter_secure_storage, local_auth, image handling |
| Web | React 19, TypeScript, Vite 8, oxlint |
| Security | Auth middleware, database-backed rate limits, OTP cooldown/expiry, image type validation |
| Planned infrastructure | Redis, Docker, WebSockets, GitHub Actions, and AWS-oriented deployment are documented intentions; they are not active repository components |

## Backend Modules

| Module | Responsibility |
| --- | --- |
| handlers/ | HTTP input/output and endpoint handling |
| services/ | Authentication, vehicles, rides, search, bookings, schedules, notifications, ratings, email |
| middleware/ | Bearer-session authentication and rate limiting |
| models/ | Request/response and domain models |
| storage/ | Local and Supabase object-storage implementations |
| database/ | PostgreSQL connection setup |
| routes/ | Central endpoint registration |

## Data Model

The current schema contains these main tables:

- users — the single identity model for all platform users.
- user_sessions, otp_verifications, rate_limits — authentication, sessions, and abuse protection.
- vehicles — user-owned vehicle records and supporting images/documents.
- rides — driver, vehicle, route, timing, capacity, fare, lifecycle, and selfie/publication data.
- bookings and booking_passengers — reservations and seat occupants.
- saved_locations, notifications, and recurring_schedules — user productivity and communication features.
- Rating data is handled by the ratings service and associated schema objects.

Indexes support ride route/date search, ride status/driver/vehicle lookup, booking lookup by ride/passenger/status, OTP/session expiry, and user schedules.

## API Surface

The Go API (default local port :8080) exposes:

- GET /health
- Authentication and account endpoints under /auth/*
- Vehicle endpoints under /vehicles and /upload/vehicle-image
- Ride creation, search, detail, and lifecycle endpoints under /rides/*
- Booking endpoints under /bookings/*
- Saved locations under /locations
- Notifications under /notifications
- Recurring schedules under /recurring-schedules/*
- Ratings under /ratings/*

Most personal or state-changing endpoints require Authorization: Bearer <session-token>. Public ride search and ride detail are exceptions.

## Local Development

### Backend

1. Copy backend/.env.example to backend/.env and supply database, SMTP, and storage settings.
2. Apply the intended SQL schema/migrations from database/ to PostgreSQL.
3. From backend/, run go run .

### Mobile

From mobile/, run flutter pub get, then run the desired Flutter target. Configure the API base URL for the target device/emulator.

### Web

From either web directory, run npm install then npm run dev. Build with npm run build and lint with npm run lint.

## Engineering Priorities

1. Treat the mobile app and API as the product core; define the web journeys before building out both web clients.
2. Keep PostgreSQL authoritative; use Redis only for cache or ephemeral workload needs.
3. Expand automated integration coverage for booking concurrency, capacity, lifecycle transitions, and authorization.
4. Add deployment configuration, secret management, observability, backups, and CI before production rollout.
5. Keep credentials in environment variables. Before deployment, remove any connection-oriented defaults in backend configuration and require explicit production values.

## Repository Map

```text
backend/       Go API and domain logic
mobile/        Flutter mobile application
customer-web/  React customer web client
admin-web/     React admin web client
database/      Current SQL schema and migrations
docs/          Architecture documentation
```

## Source of Truth

This is a codebase snapshot based on the SQL schema, backend route registration, and project manifests. For exact endpoint behavior, see backend/routes/routes.go; for exact database definitions, see database/schema/current_schema.sql.

