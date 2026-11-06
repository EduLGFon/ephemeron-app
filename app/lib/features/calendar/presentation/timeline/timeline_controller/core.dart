part of '../timeline_controller.dart';

mixin TimelineInteraction {
  DateTime get anchor;
  int get dayCount;
  WidgetRef get ref;
  BuildContext get context;
  bool get mounted;
  void setState(VoidCallback fn);

  final ScrollController scroll = ScrollController();
  String? dragId;
  double dragDy = 0;
  int dragDayDelta = 0;
  double dragOffset = 0;
  double dragXOffset = 0;
  double lastColW = 1;
  String? pendingMovedId;
  bool didJump = false;
  double scale = 1;
  double? restoredScrollOffset;
  Timer? _scalePersistTimer;
  Timer? _scrollPersistTimer;
  double autoScale = 1;
  final Map<int, Offset> pointers = {};
  double? pinchStartDist;
  double pinchBaseScale = 1;

  double swipeOffset = 0;
  bool swipeDragging = false;
  bool swipeDisabled = false;
  Animation<double>? swipeAnimation;
  int _swipeGeneration = 0;
  late AnimationController swipeController;

  double get hourHeight => timelineBaseHourHeight * autoScale * scale;

  void initTimelineInteraction() {
    swipeController =
        AnimationController(
          vsync: this as TickerProvider,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final animation = swipeAnimation;
          if (animation != null) {
            setState(() => swipeOffset = animation.value);
          }
        });
    scroll.addListener(_onScrollTick);
  }

  void _onScrollTick() {
    _scrollPersistTimer?.cancel();
    _scrollPersistTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!scroll.hasClients) return;
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        await repo.setTimelineScrollOffset(scroll.offset);
      } catch (_) {}
    });
  }

  void refreshTimelineWindow() {
    dragId = null;
    dragDy = 0;
  }

  void swipeAbort() {
    _swipeGeneration++;
    swipeController.stop();
    swipeAnimation = null;
    swipeDragging = false;
    if (swipeOffset != 0) setState(() => swipeOffset = 0);
  }

  void disposeTimelineInteraction() {
    _scalePersistTimer?.cancel();
    _scrollPersistTimer?.cancel();
    final scaleNow = scale;
    final offsetNow = scroll.hasClients ? scroll.offset : null;
    unawaited(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        await repo.setTimelineScale(scaleNow);
        if (offsetNow != null) {
          await repo.setTimelineScrollOffset(offsetNow);
        }
      } catch (_) {}
    }());
    swipeController.dispose();
    scroll.dispose();
  }

  void maybeJump() {
    if (didJump || !scroll.hasClients) return;
    didJump = true;
    if (restoredScrollOffset != null) {
      scroll.jumpTo(
        restoredScrollOffset!.clamp(0.0, scroll.position.maxScrollExtent),
      );
      restoredScrollOffset = null;
      return;
    }
    final now = DateTime.now();
    final todayIdx = _todayIndex(now);
    final hour = todayIdx >= 0 ? now.hour + now.minute / 60.0 : 8.0;
    final y = (hour - 1).clamp(0.0, 23.0) * hourHeight;
    scroll.jumpTo(y.clamp(0.0, scroll.position.maxScrollExtent));
  }

  int _todayIndex(DateTime now) {
    for (var i = 0; i < dayCount; i++) {
      final d = timelineDayStart(anchor, i);
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return i;
      }
    }
    return -1;
  }
}
