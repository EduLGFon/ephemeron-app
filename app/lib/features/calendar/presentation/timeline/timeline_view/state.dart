part of '../timeline_view.dart';

mixin _TimelineViewStateMixin
    on
        ConsumerState<TimelineView>,
        TimelineInteraction,
        TimelineSwipe,
        TimelineScale,
        TimelineDrag,
        WidgetsBindingObserver {
  List<OccurrenceCacheData> _lastOccurrences = const [];
  bool _tickerEnabled = true;

  @override
  DateTime get anchor => widget.anchor;

  @override
  int get dayCount => widget.dayCount;

  @override
  void initState() {
    super.initState();
    initTimelineInteraction();
    WidgetsBinding.instance.addObserver(this);
    _restoreTimelineState();
  }

  Future<void> _restoreTimelineState() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      if (!mounted) return;
      final savedScale = repo.timelineScale;
      if (savedScale != scale) setState(() => scale = savedScale);
      restoredScrollOffset = repo.timelineScrollOffset;
    } catch (_) {}
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeJump();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled && !_tickerEnabled) {
      ref.read(timelineNowControllerProvider).refresh();
    }
    _tickerEnabled = enabled;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(timelineNowControllerProvider).refresh();
    }
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor || old.dayCount != widget.dayCount) {
      refreshTimelineWindow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeTimelineInteraction();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      (this as _TimelineViewState)._buildTimeline(context);
}
