// Horizontal swipe wrapper for calendar views. Follows the finger, then
// snaps to the adjacent period by asking the screen to shift the anchor.
// Multi-day views shift one day at a time; the month view shifts one month.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class CalendarSwipe extends StatefulWidget {
  const CalendarSwipe({
    super.key,
    required this.child,
    required this.onShift,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<int> onShift;
  final bool enabled;

  @override
  State<CalendarSwipe> createState() => _CalendarSwipeState();
}

class _CalendarSwipeState extends State<CalendarSwipe>
    with SingleTickerProviderStateMixin {
  static const _flingVelocity = 300.0;
  static const _snapFraction = 0.2;
  static const _duration = Duration(milliseconds: 180);

  late final AnimationController _controller;
  Animation<double>? _animation;
  double _offset = 0;
  double _width = 0;
  int _pointers = 0;
  bool _ignoreDrag = false;
  bool _dragging = false;
  bool _animating = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addListener(() {
        final animation = _animation;
        if (animation != null) {
          setState(() => _offset = animation.value);
        }
      });
  }

  @override
  void didUpdateWidget(CalendarSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _dragging = false;
      _abortMotion();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers++;
    if (_pointers > 1) {
      // Pinch and multi-touch must never navigate the calendar.
      _ignoreDrag = true;
      _dragging = false;
      _abortMotion();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _ignoreDrag = false;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _ignoreDrag || _animating) {
      _dragging = false;
      return;
    }
    _width = context.size?.width ?? 0;
    if (_width <= 0) {
      _dragging = false;
      return;
    }
    _dragging = true;
    _offset = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging || _ignoreDrag || _animating) return;
    final next = (_offset + details.delta.dx).clamp(-_width, _width);
    setState(() => _offset = next);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_dragging || _ignoreDrag || !widget.enabled) {
      _dragging = false;
      return;
    }
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final fling = velocity.abs() > _flingVelocity;
    final passed = _offset.abs() > _width * _snapFraction;
    if (!fling && !passed) {
      await _snapBack();
      return;
    }
    final direction = fling ? -velocity.sign.toInt() : -_offset.sign.toInt();
    if (direction == 0) {
      await _snapBack();
      return;
    }
    await _reverse(direction);
  }

  void _onDragCancel() {
    _dragging = false;
    if (_offset != 0) _snapBack();
  }

  Future<void> _reverse(int direction) async {
    final generation = ++_generation;
    _animating = true;
    await _animateTo(-direction * _width);
    if (!mounted || generation != _generation) return;
    widget.onShift(direction);
    setState(() => _offset = direction * _width);
    await _animateTo(0);
    if (!mounted || generation != _generation) return;
    _animating = false;
  }

  Future<void> _snapBack() async {
    final generation = ++_generation;
    _animating = true;
    await _animateTo(0);
    if (!mounted || generation != _generation) return;
    _animating = false;
  }

  void _abortMotion() {
    _generation++;
    _controller.stop();
    _animation = null;
    _animating = false;
    if (_offset != 0) setState(() => _offset = 0);
  }

  Future<void> _animateTo(double target) async {
    final begin = _offset;
    if ((begin - target).abs() < 0.5) {
      if (mounted) setState(() => _offset = target);
      return;
    }
    _animation = Tween<double>(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.reset();
    try {
      await _controller.forward().orCancel;
    } on TickerCanceled {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
