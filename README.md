# AbhiShare

AbhiShare is a vehicle-sharing platform that connects people traveling in the same direction so they can share available seats in a vehicle.

## Core Concept

Drivers create planned rides and offer available seats.

Passengers search for matching rides and book available seats.


Driver
   ↓
Create Ride
   ↓
AbhiShare Platform
   ↓
Passenger Searches
   ↓
Passenger Books Seat
   ↓
Driver Confirms

Vehicle Categories
2-seater — motorcycles, scooters and other two-wheelers
5-seater — cars
7-seater — larger cars, SUVs and MPVs
The architecture should support additional vehicle categories in the future.
Technology
Mobile
Flutter
Dart
Web
React
TypeScript
Vite
Backend
Go
Fiber
REST APIs
WebSocket
Database
PostgreSQL
Supporting Infrastructure
Redis
S3-compatible object storage
Docker
GitHub Actions
AWS-oriented cloud infrastructure
Repository Structure
abhishare/
├── backend/          # Go backend API
├── mobile/           # Flutter Android/iOS application
├── customer-web/     # Customer web application
├── admin-web/        # Admin web application
├── database/         # Database schemas and migrations
├── docs/             # Architecture and product documentation
└── infrastructure/   # Infrastructure and deployment configuration
Development Philosophy
Build in this order:
Working → Correct → Secure → Scalable → Beautiful
The first critical product loop is:
Create Ride
     ↓
Search Ride
     ↓
Book Seat
     ↓
Driver Accepts
     ↓
Ride Happens
     ↓
Rating / Review