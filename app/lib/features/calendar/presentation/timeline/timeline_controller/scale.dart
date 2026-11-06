part of '../timeline_controller.dart';

mixin TimelineScale on TimelineInteraction {
  void applyScale(double next) {
    next = next.clamp(timelineMinScale, timelineMaxScale);
    if (next == scale) return;
    final ratio = next / scale;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    setState(() => scale = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.jumpTo(
        (offset * ratio).clamp(0.0, scroll.position.maxScrollExtent),
      );
    });
    _scalePersistTimer?.cancel();
    _scalePersistTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        await repo.setTimelineScale(scale);
      } catch (_) {}
    });
  }

  KeyEventResult onTimelineKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        applyScale(scale * 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        applyScale(scale / 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        applyScale(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  double _pointerDist() {
    final pts = pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void onTimelinePointerDown(PointerDownEvent e) {
    pointers[e.pointer] = e.position;
    if (pointers.length == 2) {
      pinchStartDist = _pointerDist();
      pinchBaseScale = scale;
      swipeDisabled = true;
      swipeAbort();
    }
  }

  void onTimelinePointerMove(PointerMoveEvent e) {
    if (!pointers.containsKey(e.pointer)) return;
    pointers[e.pointer] = e.position;
    if (pointers.length == 2 && pinchStartDist != null && pinchStartDist! > 0) {
      applyScale(pinchBaseScale * _pointerDist() / pinchStartDist!);
    }
  }

  void onTimelinePointerEnd(PointerEvent e) {
    pointers.remove(e.pointer);
    if (pointers.length < 2) pinchStartDist = null;
    if (pointers.isEmpty) swipeDisabled = false;
  }
}
