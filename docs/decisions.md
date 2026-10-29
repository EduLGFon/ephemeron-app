# Decisions

Decisions not covered by PLAN.md (lighter-weight option chosen by default).

- Cancelled exception rows act as EXDATE equivalents; no separate EXDATE column.
- Root `.gitignore` bare `test` rule ignores new test files; force-add them.
- Widget tests: close in-memory Drift DB and unmount inside the test body
  before the final pump; otherwise Drift's stream-close zero-timer trips the
  pending-timer check (addTearDown close runs too late).
