# iOS home-screen widgets (owner/Xcode work)

Status: not implemented. This task requires macOS + Xcode and cannot be completed
or verified on the Linux build environment. Do not add WidgetKit targets,
entitlements wiring, or `project.pbxproj` edits from Linux; they would be
unverifiable and likely broken.

## What already exists

- Android widget providers and layouts under `app/android/.../HomeWidgets.kt`,
  `WeekCalendarWidget.kt`, and `CollectionWidgets.kt`.
- Dart widget definitions and refresh binding in
  `app/lib/data/services/home_widget_service.dart` and related services.
- The `home_widget` plugin is treated as supported on iOS in
  `app/lib/data/services/home_widget_support.dart`, so no Dart-side platform
  guard change is needed for iOS.

## Owner steps (Xcode/macOS)

1. Regenerate iOS platform scaffolding if needed (`flutter create .` in `app/`),
   then open `app/ios/Runner.xcworkspace` in Xcode.
2. Add a WidgetKit extension target.
3. Enable App Groups for both the Runner target and the extension, using one
   shared group id.
4. Publish that group id to Dart and call `HomeWidget.setAppGroupId(...)` before
   widget data is written (no such call exists yet).
5. Implement SwiftUI views that read the shared keys written by `home_widget`
   (title/body/image keys per provider, matching the Android key prefixes).
6. Register every widget kind in the extension's widget bundle and Info.plist.
7. Build and run on an iOS simulator/device; verify rendering, refresh, and
   deep links (`ephemeron://...`).

## Non-Xcode preparatory work (optional, owner-approved)

- Choose and document the App Group identifier.
- Add a Dart constant for it and call `HomeWidget.setAppGroupId`.
- Keep key prefixes aligned with `home_widget_service.dart`.

These are intentionally left undone here because the group id and extension
contract must be settled in Xcode first.