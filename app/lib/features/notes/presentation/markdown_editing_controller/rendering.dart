part of '../markdown_editing_controller.dart';

extension _MarkdownRendering on MarkdownEditingController {
  TextSpan _buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final text = value.text;
    final segments = _segmentsFor(text);
    final composing = value.composing;
    final hasComposing =
        withComposing && composing.isValid && value.isComposingRangeValid;

    final children = <TextSpan>[];
    var offset = 0;
    for (final seg in segments) {
      final segStart = offset;
      final segEnd = offset + seg.text.length;
      final segStyle = _styleFor(seg, base, context);
      if (!hasComposing ||
          segEnd <= composing.start ||
          segStart >= composing.end) {
        children.add(TextSpan(text: seg.text, style: segStyle));
      } else {
        final localStart = (composing.start - segStart).clamp(
          0,
          seg.text.length,
        );
        final localEnd = (composing.end - segStart).clamp(0, seg.text.length);
        if (localStart > 0) {
          children.add(
            TextSpan(text: seg.text.substring(0, localStart), style: segStyle),
          );
        }
        if (localEnd > localStart) {
          children.add(
            TextSpan(
              text: seg.text.substring(localStart, localEnd),
              style: segStyle.copyWith(decoration: TextDecoration.underline),
            ),
          );
        }
        if (localEnd < seg.text.length) {
          children.add(
            TextSpan(text: seg.text.substring(localEnd), style: segStyle),
          );
        }
      }
      offset = segEnd;
    }
    return TextSpan(style: base, children: children);
  }

  List<_Segment> _segmentsFor(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    final parsed = _parse(text);
    if (_cache.length >= MarkdownEditingController._maxCacheEntries) {
      _cache.clear();
    }
    _cache[text] = parsed;
    return parsed;
  }

  TextStyle _styleFor(_Segment seg, TextStyle base, BuildContext context) {
    final theme = Theme.of(context);
    if (seg.marker) {
      return base.copyWith(
        color: (base.color ?? theme.colorScheme.onSurface).withValues(
          alpha: 0.4,
        ),
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        decoration: TextDecoration.none,
      );
    }
    var s = base;
    if (seg.flags & _kBold != 0) s = s.copyWith(fontWeight: FontWeight.bold);
    if (seg.flags & _kItalic != 0) s = s.copyWith(fontStyle: FontStyle.italic);
    if (seg.flags & _kCode != 0) {
      s = s.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      );
    }
    if (seg.flags & _kStrike != 0) {
      s = s.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (seg.flags & _kLink != 0) {
      s = s.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      );
    }
    if (seg.flags & _kHeading != 0) {
      final level = seg.headingLevel.clamp(1, 6);
      s = s.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (base.fontSize ?? 14) + (7 - level),
      );
    }
    if (seg.flags & _kBlockquote != 0) {
      s = s.copyWith(fontStyle: FontStyle.italic);
    }
    return s;
  }
}
