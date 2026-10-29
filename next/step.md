# Rewrite Progress

## Current Step
Project builds for web and tests pass; unused native plugin deps removed.

## Completed
- Project scaffold in `next/`
- Database schema & generated code
- Alarm domain (AlarmPreset, ReminderOffset, AlarmScheduler stub)
- Task repository + recurrence + smart lists + calendar entries
- Countdown repository + status/type
- Calendar recurrence config
- Minimal app entry, CalendarScreen, providers
- All existing tests passing

## Next Steps
1. Implement core theme/settings/bootstrap/routing/shell.
2. Implement feature UI screens (calendar, tasks, habits, focus, notes, matrix, countdown).
3. Implement sync, tags, quick_add.
4. Add remaining feature data layers (habits, focus, notes) with tests.
5. Run full analyze and tests; commit incremental changes.