part of '../markdown_editing_controller.dart';

const int _kBold = 1 << 0;
const int _kItalic = 1 << 1;
const int _kCode = 1 << 2;
const int _kStrike = 1 << 3;
const int _kLink = 1 << 4;
const int _kHeading = 1 << 5;
const int _kBlockquote = 1 << 6;

class _Segment {
  const _Segment(
    this.text,
    this.flags, {
    this.marker = false,
    this.headingLevel = 0,
  });

  final String text;
  final int flags;
  final bool marker;
  final int headingLevel;
}
