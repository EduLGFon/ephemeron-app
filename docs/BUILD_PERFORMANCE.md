# Android build performance

Notes from profiling `flutter build apk` on the owner's laptop (2026-11-03).
The goal is a faster local release build without weakening release
optimizations.

## Machine and toolchain

| Item | Value |
| --- | --- |
| CPU | Intel i7-6500U, 2 cores / 4 threads, 15 W |
| RAM | 15.5 GB, 15.5 GB zram swap |
| Disk | Seagate ST1000LM014, 5400 RPM hybrid HDD (`ROTA=1`) |
| Flutter | 3.47.8 (Dart 3.13.7) |
| Android | AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0 |
| JDK | Android Studio JBR 25.0.4 |

The HDD and the two physical cores are the hard limits. No Gradle flag makes
this machine build like an SSD or an 8-core laptop.

## Where the time goes

1. Dart kernel compilation (`frontend_server`): one process, ~1.5 GB RSS.
   Incremental when `build/` and `.dart_tool/` are warm.
2. AOT compilation: Flutter starts one `gen_snapshot` per target ABI. A
   default `flutter build apk` targets `android-arm`, `android-arm64` and
   `android-x64`, so three AOT processes run at once and fight over four
   hardware threads.
3. Gradle configuration plus Kotlin/Java compilation of the app and the
   plugin subprojects.
4. R8 minification and resource shrinking (release only, always on).
5. APK merge, zip, hashing and signing. The zip/hash pass is I/O bound and
   hurts on a 5400 RPM disk.

## Applied changes

`app/android/gradle.properties`:

- Keep the template `-Xmx8G`. A 4 GB cap was tested and made things worse:
  ParallelGC filled the old generation and the build sat in full GC. The
  daemon only commits what it needs, so a high cap is not the problem.
- `-XX:MaxMetaspaceSize=1G` (the daemon used about 170 MB).
- `org.gradle.caching=true` for AGP/Kotlin task outputs. Flutter's own
  `FlutterTask` is not cacheable, so this mainly helps clean builds and
  branch switches.
- `org.gradle.daemon=true` and `kotlin.daemon.jvmargs=-Xmx2G`.
- `android.enableJetifier=false`, `android.nonTransitiveRClass=true`.
- `org.gradle.configuration-cache=false` on purpose. The Flutter Gradle plugin
  is not configuration-cache compatible (flutter/flutter#192035), so enabling
  it fails the build.
- `org.gradle.parallel=true` was tested and dropped. This project is one app
  module plus plugin subprojects, and one build already saturates four
  threads; parallel only added memory pressure.

`tools/build_apk.sh` builds a single ABI by default:

```sh
tools/build_apk.sh              # release, arm64
tools/build_apk.sh x64          # release for an x86_64 emulator
tools/build_apk.sh --dev        # no R8, no icon tree-shaking, larger APK
```

The script keeps Flutter's implicit `pub get`. It also regenerates
`GeneratedPluginRegistrant.java` with the release plugin set. Do not add
`--no-pub` here: it skips that regeneration, so a registrant written by a debug
build (which includes `integration_test`) is left in place and
`compileReleaseJavaWithJavac` fails.

Use `flutter run` with hot reload for day-to-day iteration. A release APK is
the slowest way to test a Dart change.

## `flutter run` (dev loop)

`flutter run` has a different cost profile: no R8, but Gradle still runs
`assembleDebug` on every launch. Measurements below are wall time until the
tool emits `app.started` on the SM A556E and on the Linux desktop.

| Target | Command | Time |
| --- | --- | --- |
| Linux, cold `build/linux` | `flutter run -d linux` | 1:30 |
| Linux, warm | `flutter run -d linux` | 0:22 |
| Android, cold | `flutter run -d <device>` | 3:15 |
| Android, warm | `flutter run -d <device>` | 0:37 to 1:00 |
| Android, prebuilt APK | `tools/run_android.sh -d <device>` | 0:12 |

Warm Android split: ~3s tool startup, ~26s Gradle `assembleDebug`, ~8s install,
under 1s kernel sync. The debug APK is 115 MB, so install is the floor once
Gradle is gone.

`tools/run_android.sh` keeps one debug APK and launches it with
`--use-application-binary`, which skips Gradle entirely. It rebuilds the APK
only when native inputs change (Android sources, Gradle files, `pubspec.yaml`
or `pubspec.lock`), or when passed `--rebuild`. Dart, asset and font changes
are pushed by the tool's devfs sync on the next run, so they do not need a
rebuild. The first invocation pays for one `flutter build apk --debug`
(about 2:30 here); every later launch is about 12s.

```sh
tools/run_android.sh -d RQCXA02094D            # fast loop
tools/run_android.sh -d RQCXA02094D --rebuild  # after a plugin or native change
ABI=x64 tools/run_android.sh                    # emulator
```

Linux has no prebuilt-binary support. Its warm 22s is the debug kernel build
plus engine start, and no flag removes it. Keep one `flutter run -d linux`
session and press `r` instead of restarting the tool.

## Web (`flutter run -d chrome`)

Web debug builds have no AOT and no Gradle step. The DDC compile is the whole
cost, and it does not survive a restart of the tool.

| Target | Command | Time |
| --- | --- | --- |
| Chrome, first run | `flutter run -d chrome` | 1:46 |
| Chrome, later runs | `flutter run -d chrome` | 1:41 to 1:49 |
| Web server, URL ready | `flutter run -d web-server` | 1:38 |

Every new `flutter run -d chrome` recompiles the app for the web; a warm
`.dart_tool/flutter_build` does not shorten it. A live session is the only fast
path: `R` recompiles incrementally in under a second here (861ms measured) and
then reloads the page.

- Keep one `flutter run -d chrome` session and use `R` and `r`.
- `-d web-server` skips the Chrome launch and debug-service handshake (about
  8s here), but you open the printed URL yourself.
- `--no-web-resources-cdn` serves CanvasKit from the local SDK instead of the
  CDN. It does not change the compile time; it removes a network fetch per run
  and makes the loop work offline.

## Do not do these

- Do not run `flutter run` and `flutter build apk` at the same time. Both
  regenerate `app/android/.../GeneratedPluginRegistrant.java`. A debug build
  writes `integration_test` into it, and a concurrent release build then fails
  at `compileReleaseJavaWithJavac` because release builds exclude dev
  dependencies. Gradle also serializes on the project and file-hash caches.
  This race was observed twice during profiling: once with an Android debug
  run, and once with `flutter run -d linux`, which writes the same Android
  registrant even though it targets the desktop.
- Do not enable the Gradle configuration cache (see above).
- Do not use `--split-per-abi` to go faster. It still compiles every ABI and
  produces several APKs, so it is slower than one `--target-platform`.
- Do not run `flutter clean` routinely. It throws away the kernel cache, the
  AOT snapshots and every Gradle up-to-date check.
- Do not cap the Gradle heap at 4 GB or add `-XX:+UseParallelGC`. Both were
  tested and made the build slower: the old generation filled and the build sat
  in full GC. The 8 GB cap is only a limit, not a pre-commit.
- Do not move `build/` to tmpfs. The build tree is several GB and the machine
  already uses several GB of zram.

## System-level wins

- Free RAM before a build. During profiling the machine had ~9 GB in use,
  7.4 GB of zram swap in use and two stale `flutter_tester` processes from
  another project. Closing browsers/IDEs and stopping stale test processes
  removes CPU spent on zram compression.
- Keep the laptop on mains power. It was plugged in and the CPU reached its
  3.0 GHz turbo limit, so the `powersave` intel_pstate governor was not the
  problem.
- An SSD is the largest single improvement available on this machine.

## Optional, not applied

- AGP 9.3 and Gradle 9.5 add build-speed work, but AGP 9.3 requires Gradle
  9.5 and a migration. Do it as its own change, with a build-size and behavior
  comparison.
- R8 can run in a separate JVM (`android.settings` execution profiles). That
  helps memory-rich machines; here it would add another JVM to a machine that
  already swaps.
- Upgrading `home_widget` and `workmanager_android` to versions that support
  built-in Kotlin would remove the KGP opt-outs, but it is not a build-speed
  fix.

## Measurements

Release build times. Times are wall clock, release builds, same source tree,
no concurrent build. For `flutter run` numbers, see the section above.

| Build | Command | Time |
| --- | --- | --- |
| Single-ABI release, warm `build/` | `tools/build_apk.sh arm64` | 3:40 (220.5s) |
| Single-ABI release, no changes | `tools/build_apk.sh arm64` | 0:25 (25.0s) |
| Single-ABI dev, warm `build/` | `tools/build_apk.sh --dev arm64` | 0:53 (52.9s), 34.1 MB APK |

The `--dev` row reused the release `build/` tree, so it mostly measures skipping
R8 and recompiling Java, not a from-scratch dev build. `--dev` writes the same
`app-release.apk` path, so it overwrites the optimized APK; rebuild with the
plain script when you need the release artifact.

The 3-ABI baseline was not measured to completion. The first attempt failed at
`compileReleaseJavaWithJavac` after 9:01 because a concurrent `flutter run`
had rewritten `GeneratedPluginRegistrant.java` with `integration_test` in it.
That attempt proves a full 3-ABI release build takes over nine minutes here,
but it is not a valid clean number. A second 3-ABI attempt was abandoned when a
4 GB heap experiment sent the daemon into full GC.

The two release rows use the same source tree. The 3:40 row is an incremental
build that still had to run AOT, R8 and packaging; the 0:25 row is a no-op
rebuild where every task was up to date. A build after a Dart-only change lands
between them, closer to the 3:40 end because AOT and packaging rerun.
