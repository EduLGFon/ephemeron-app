# Phase 1 - Foundation

Checklist (PLAN.md section 14, phase 1):

- [x] Flutter project with folder layout (core, data, domain, features, app)
- [x] CI workflow: format, strict analyze, tests, release size report
- [x] Theme tokens: 10 primary presets + custom hex, 6 background presets + custom hex, light/dark/AMOLED, bundled subsetted Fraunces and Inter
- [x] App shell: 7 sections, top 5 pinned + More sheet, drag reorder, floating pill and edge-to-edge, go_router StatefulShellRoute.indexedStack, last-screen restore, empty states
- [x] Drift DB: full schema, indexes, FTS5, versioned migrations, WAL/pragmas, background isolate native, WASM/OPFS web, migration + in-memory repo tests
- [x] Settings storage: appearance, nav order, power saving, reduce animations, haptics + basic settings screen
- [x] Logger: 500-line cap, no personal data/tokens
- [x] Lazy provider init: first frame never blocked

Measured numbers recorded at end of phase.