# AbhiShare 2.0 — Technical Architecture

## 1. Overview

AbhiShare is a vehicle-sharing platform where drivers create planned rides and passengers discover and book available seats.

The platform consists of mobile applications, web applications, a backend API, a relational database, and supporting infrastructure.

---

## 2. High-Level Architecture

                    ABHISHARE
                        │
          ┌─────────────┼─────────────┐
          │             │             │
       Android         iOS           Web
       Flutter        Flutter        React
          │             │             │
          └─────────────┼─────────────┘
                        │
                      HTTPS
                        │
                 REST + JSON API
                        │
                        ▼
                  Go + Fiber API
                        │
             ┌──────────┼──────────┐
             │          │          │
             ▼          ▼          ▼
       PostgreSQL     Redis      Object
         Cloud        Cloud      Storage
             │
             ▼
       AbhiShare Data