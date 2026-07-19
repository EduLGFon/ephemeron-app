# Ephemeron

Ephemeron is a highly efficient, cross-platform calendar, habit, and task management application built with Flutter. It focuses on battery efficiency, smooth performance, and preserving privacy through a CASA-avoidant architecture.

## Features

- **Unified Task & Event Management**: Combines Google Calendar events and Google Tasks into a single workflow.
- **Privacy-First (CASA-Avoidant)**: Ephemeron connects directly to Google APIs from the client. Your Google tokens and data never touch a centralized backend.
- **Habit Tracking**: Track daily, weekly, or interval-based habits with rich metrics and streak calculations.
- **Focus Timer**: Built-in Pomodoro/Stopwatch timer that seamlessly integrates with your tasks and habits.
- **Countdowns**: Track days remaining until holidays, birthdays, or custom events.
- **Advanced Alarm Engine**: Robust offline alarm scheduling utilizing native OS features for minimum battery consumption.
- **Quick Add Shorthand**: Quickly create tasks or events using natural shorthand (`title #tag ~list -p4`).

## Tech Stack

- **Framework**: Flutter
- **State Management & DI**: Riverpod
- **Routing**: `go_router` (Stateful nested navigation with `StatefulShellRoute`)
- **Local Database**: Drift (SQLite)
- **Authentication**: `google_sign_in` (v7) for Google APIs, independent backend auth for custom sync.

## Architecture Highlights

- **Two Independent Connections**: The app maintains two completely isolated authentication states. Google Calendar/Tasks data is synced directly with Google's servers, while the backend connection is reserved strictly for custom app data (like habits and focus sessions).
- **Offline-First**: Tasks, habits, and countdowns are stored locally via Drift.
- **Performance & Battery**: 
  - Uses `battery_plus` to detect power-saving mode and adapt animations automatically.
  - Avoids background polling where possible; sync is either user-initiated or triggered by efficient background tasks.
  - Bundles fonts (`Fraunces` and `Inter`) locally to prevent runtime network fetches.

## Getting Started

### Prerequisites

1. **Flutter SDK** (stable channel).
2. Local font assets: Download `Fraunces` (Regular/SemiBold) and `Inter` (Regular/Medium/SemiBold) from Google Fonts and place them in `assets/fonts/`.

### Installation

1. Clone the repository and navigate to the root directory.
2. If you are building for desktop, ensure they are enabled:
   ```bash
   flutter config --enable-linux-desktop --enable-windows-desktop
   ```
3. Generate the required platform folders (if missing):
   ```bash
   flutter create --org com.yourcompany.ephemeron .
   ```
4. Install dependencies:
   ```bash
   flutter pub get
   ```
5. Generate Drift database classes (required to compile):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
   *(Use `watch` instead of `build` during active development).*
6. Run the app:
   ```bash
   flutter run
   ```

### Google Cloud Console Setup (OAuth)

To enable Google Calendar and Tasks integration:
1. Create an Android OAuth client (using your package name and SHA-1 fingerprint) and a Web application OAuth client in the Google Cloud Console.
2. Update `AppConfig.googleWebClientId` with your Web client ID.
3. The Android client authenticates automatically based on the application signature (no client ID string required in the code).

## Development Notes

- **State Management**: We use `Riverpod` exclusively for both state management and dependency injection. Avoid adding separate service locators.
- **Alarms**: Ephemeron utilizes `flutter_local_notifications`. On Android, `USE_EXACT_ALARM` is required to ensure alarms fire precisely, even in Doze mode.
- **Web Limitations**: Background alarm scheduling and Drift SQLite operations have specific limitations on the Web platform. These features are gracefully disabled or require WebAssembly/OPFS setups.

## Contributing

All code must be cross-platform (Android max priority, Linux/Web medium, Windows low). Follow the strict rule of maximizing battery efficiency and ensuring the app runs as smoothly and lightweight as possible. Run `flutter analyze` before submitting any changes.
