# ZHANAR Massage Academy

A bilingual iOS learning app and companion web portal for a massage academy. Built with SwiftUI and a Node.js web server, with Supabase authentication and content storage.

## What it includes

- Kazakh and Russian interface
- Course catalog, lesson library, and progress sync
- Private lesson video playback
- StoreKit 2 course purchases and restore flow on iOS
- Web sign-in and learner portal
- Admin tools for managing courses and course assets

## Tech stack

SwiftUI · StoreKit 2 · Node.js · Supabase · PostgreSQL

## Project structure

- `Massage app/` — iOS application
- `Massage app.xcodeproj/` — Xcode project and StoreKit test configuration
- `web/` — browser portal and server
- `supabase/` — schema, migrations, and edge functions
- `tests/`, `tests-swift/` — automated tests

## Run the iOS app

Open `Massage app.xcodeproj` in Xcode, select the shared **Massage app** scheme, and run it on an iOS simulator or device. The Debug build includes a preview mode for exploring the interface.

## Run the web app

Use Node.js 22.13 or newer:

```sh
cd web
cp .env.example .env
# Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env
npm ci
npm run dev
```

The local site is available at `http://localhost:4173`. See [`web/README.md`](web/README.md) for deployment configuration and additional details.

## Configuration

The web app reads its Supabase URL and publishable key from environment variables. Do not commit `.env` files, credentials, or service-role keys. The iOS client uses a Supabase publishable key; privileged operations are handled by server-side policies and functions.

## Status

This repository contains the application source and supporting project configuration. Production services, course content, and store setup depend on the academy's own accounts and release configuration.
