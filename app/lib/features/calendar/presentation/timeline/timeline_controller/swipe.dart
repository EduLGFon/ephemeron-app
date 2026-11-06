part of '../timeline_controller.dart';

mixin TimelineSwipe on TimelineInteraction {
  void onSwipeStart(DragStartDetails details) {
    if (swipeController.isAnimating) swipeAbort();
    if (dragId != null) {
      swipeDragging = false;
      return;
    }
    if (pointers.length > 1) {
      swipeDisabled = true;
      swipeDragging = false;
      return;
    }
    swipeDisabled = false;
    swipeDragging = true;
    swipeOffset = 0;
    swipeAnimation = null;
  }

  void onSwipeUpdate(DragUpdateDetails details) {
    if (!swipeDragging || swipeDisabled || dragId != null) return;
    final step = lastColW.clamp(1.0, double.infinity);
    final limit = step * timelineBufferDays;
    swipeOffset = (swipeOffset + details.delta.dx).clamp(-limit, limit);
    setState(() {});
  }

  Future<void> onSwipeEnd(DragEndDetails details) async {
    if (!swipeDragging) {
      swipeDragging = false;
      return;
    }
    swipeDragging = false;
    if (swipeDisabled || dragId != null) {
      await _swipeSnapBack();
      return;
    }
    final step = lastColW.clamp(1.0, double.infinity);
    final velocity = details.primaryVelocity ?? 0;
    final projected = swipeOffset + velocity * 0.12;
    var days = (-projected / step).round();
    days = days.clamp(-timelineBufferDays, timelineBufferDays);
    if (days == 0) {
      await _swipeSnapBack();
      return;
    }
    await _swipeReverse(days, step);
  }

  void onSwipeCancel() {
    swipeDragging = false;
    if (swipeOffset != 0) _swipeSnapBack();
  }

  Future<void> _swipeReverse(int days, double step) async {
    final generation = ++_swipeGeneration;
    swipeController.duration = Duration(
      milliseconds: (180 + (days.abs() - 1) * 45).clamp(180, 600),
    );
    await _swipeAnimateTo(-days * step);
    if (!mounted || generation != _swipeGeneration) return;
    ref.read(calendarStateProvider.notifier).shift(days);
    setState(() => swipeOffset = 0);
  }

  Future<void> _swipeSnapBack() async {
    final generation = ++_swipeGeneration;
    swipeController.duration = const Duration(milliseconds: 180);
    await _swipeAnimateTo(0);
    if (!mounted || generation != _swipeGeneration) return;
  }

  Future<void> _swipeAnimateTo(double target) async {
    final begin = swipeOffset;
    if ((begin - target).abs() < 0.5) {
      if (mounted) setState(() => swipeOffset = target);
      return;
    }
    swipeAnimation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: swipeController, curve: Curves.easeOutCubic),
    );
    swipeController.reset();
    try {
      await swipeController.forward().orCancel;
    } on TickerCanceled {
      return;
    }
  }
}
