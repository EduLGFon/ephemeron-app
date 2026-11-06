part of '../habit_editor_sheet.dart';

abstract class _HabitEditorSheetStateBase extends ConsumerState<_HabitEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  late final TextEditingController _step;
  String _unitPreset = 'custom';
  String? _sectionId;
  String _frequency = 'daily';
  int _weekdaysMask = 127;
  int _weeklyTarget = 3;
  int _intervalDays = 2;
  late String _startDate;
  String? _reminderTime;
  String? _alarmPreset;
  DraftAutosaver? _saver;
  bool _saved = false;
  SettingsRepository? _settings;

  String get _draftEntityId => widget.habit?.id ?? 'new';

  String _expectedSheet() =>
      widget.habit == null ? 'habit_new' : 'habit:${widget.habit!.id}';
}

abstract class _HabitEditorSheetStateWithActions
    extends _HabitEditorSheetStateBase with _HabitEditorSheetStateActions {}

class _HabitEditorSheetState extends _HabitEditorSheetStateWithActions
    with _HabitEditorSheetStateView {
  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    final d = widget.restoredDraft;
    _name = TextEditingController(
      text: (d?['name'] as String?) ?? h?.name ?? '',
    );
    _amount = TextEditingController(
      text:
          (d?['amount'] as String?) ??
          (h?.goalAmount != null ? '${h!.goalAmount}' : ''),
    );
    _unit = TextEditingController(
      text: (d?['unit'] as String?) ?? h?.unit ?? '',
    );
    _step = TextEditingController(
      text:
          (d?['step'] as String?) ??
          (h?.increment != null ? '${h!.increment}' : '1'),
    );
    final initialUnit = (d?['unit'] as String?) ?? h?.unit ?? '';
    _unitPreset = (initialUnit == 'count' || initialUnit == 'min')
        ? initialUnit
        : 'custom';
    _sectionId = (d?['sectionId'] as String?) ?? h?.sectionId;
    _frequency =
        (d?['frequency'] as String?) ??
        (_frequencies.contains(h?.frequency) ? h!.frequency : 'daily');
    _weekdaysMask =
        (d?['weekdaysMask'] as num?)?.toInt() ?? h?.weekdaysMask ?? 127;
    _weeklyTarget =
        (d?['weeklyTarget'] as num?)?.toInt() ?? h?.weeklyTarget ?? 3;
    _intervalDays =
        (d?['intervalDays'] as num?)?.toInt() ?? h?.intervalDays ?? 2;
    _startDate =
        (d?['startDate'] as String?) ??
        h?.startDate ??
        habitDateKey(DateTime.now());
    _reminderTime = (d?['reminderTime'] as String?) ?? h?.reminderTime;
    _alarmPreset = (d?['alarmPreset'] as String?) ?? h?.alarmPreset;
    for (final c in [_name, _amount, _unit, _step]) {
      c.addListener(_queueDraft);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'habit',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.habit == null ? 'habit_new' : 'habit:${widget.habit!.id}',
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (!_saved) {
      final snap = _snapshot();
      _saver?.changed(() => snap);
    }
    _saver?.dispose();
    final settings = _settings;
    // Normal close clears the marker; process kill skips dispose
    // so the marker survives kills. Drafts are kept for preload.
    if (settings != null) {
      final expected = _expectedSheet();
      Future.microtask(() async {
        try {
          if (settings.openSheet == expected) {
            await settings.setOpenSheet(null);
          }
        } catch (_) {}
      });
    }
    _name.dispose();
    _amount.dispose();
    _unit.dispose();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody();
}
