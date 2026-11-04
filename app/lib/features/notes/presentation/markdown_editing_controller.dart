// A [TextEditingController] that renders raw Markdown inline while typing.
// Markers stay visible but are dimmed; storage stays plain Markdown.
// The concatenated span text always equals [text] so cursor/IME offsets
// remain valid.
import 'package:flutter/material.dart';

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

class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  final Map<String, List<_Segment>> _cache = <String, List<_Segment>>{};
  static const int _maxCacheEntries = 32;

  List<_Segment> _segmentsFor(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    final parsed = _parse(text);
    if (_cache.length >= _maxCacheEntries) _cache.clear();
    _cache[text] = parsed;
    return parsed;
  }

  @override
  TextSpan buildTextSpan({
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

  static List<_Segment> _parse(String text) {
    final out = <_Segment>[];
    final lines = text.split('\n');
    var inCode = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        out.add(_Segment(line, 0, marker: true));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        out.add(_Segment(line, _kCode));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        continue;
      }

      // Heading
      final headingMatch = RegExp(r'^(#{1,6})(.*)$').firstMatch(line);
      if (headingMatch != null) {
        final hashes = headingMatch.group(1)!;
        final rest = headingMatch.group(2)!;
        if (rest.isEmpty || rest.startsWith(' ')) {
          out.add(_Segment(hashes, 0, marker: true));
          if (rest.startsWith(' ')) {
            out.add(const _Segment(' ', 0));
            out.addAll(
              _parseInline(
                rest.substring(1),
                baseFlags: _kHeading,
                headingLevel: hashes.length,
              ),
            );
          } else {
            out.addAll(
              _parseInline(
                rest,
                baseFlags: _kHeading,
                headingLevel: hashes.length,
              ),
            );
          }
          if (i < lines.length - 1) out.add(const _Segment('\n', 0));
          continue;
        }
      }

      // Blockquote
      if (line.startsWith('>')) {
        out.add(_Segment('>', 0, marker: true));
        out.addAll(_parseInline(line.substring(1), baseFlags: _kBlockquote));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        continue;
      }

      // Task checkbox
      final taskMatch = RegExp(
        r'^(\s*)([-*+])(\s+)(\[[ xX]\])(.*)$',
      ).firstMatch(line);
      if (taskMatch != null) {
        out.add(_Segment(taskMatch.group(1)!, 0));
        out.add(_Segment(taskMatch.group(2)!, 0, marker: true));
        out.add(_Segment(taskMatch.group(3)!, 0));
        out.add(_Segment(taskMatch.group(4)!, 0, marker: true));
        out.addAll(_parseInline(taskMatch.group(5)!));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        continue;
      }

      // Bullet list
      final bulletMatch = RegExp(r'^(\s*)([-*+])(\s+)(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        out.add(_Segment(bulletMatch.group(1)!, 0));
        out.add(_Segment(bulletMatch.group(2)!, 0, marker: true));
        out.add(_Segment(bulletMatch.group(3)!, 0));
        out.addAll(_parseInline(bulletMatch.group(4)!));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        continue;
      }

      // Numbered list
      final numMatch = RegExp(r'^(\s*)(\d+\.)(\s+)(.*)$').firstMatch(line);
      if (numMatch != null) {
        out.add(_Segment(numMatch.group(1)!, 0));
        out.add(_Segment(numMatch.group(2)!, 0, marker: true));
        out.add(_Segment(numMatch.group(3)!, 0));
        out.addAll(_parseInline(numMatch.group(4)!));
        if (i < lines.length - 1) out.add(const _Segment('\n', 0));
        continue;
      }

      out.addAll(_parseInline(line));
      if (i < lines.length - 1) out.add(const _Segment('\n', 0));
    }
    return out;
  }

  static List<_Segment> _parseInline(
    String input, {
    int baseFlags = 0,
    int headingLevel = 0,
  }) {
    final out = <_Segment>[];
    var i = 0;
    final n = input.length;
    while (i < n) {
      // Inline code
      if (input[i] == '`') {
        final close = input.indexOf('`', i + 1);
        if (close > i) {
          out.add(_Segment('`', 0, marker: true));
          out.add(_Segment(input.substring(i + 1, close), _kCode | baseFlags));
          out.add(_Segment('`', 0, marker: true));
          i = close + 1;
          continue;
        }
      }
      // Link
      if (input[i] == '[') {
        final closeBracket = input.indexOf(']', i + 1);
        if (closeBracket > i) {
          final openParen = closeBracket + 1 < n ? input[closeBracket + 1] : '';
          if (openParen == '(') {
            final closeParen = input.indexOf(')', closeBracket + 2);
            if (closeParen > closeBracket) {
              out.add(_Segment('[', 0, marker: true));
              out.addAll(
                _parseInline(
                  input.substring(i + 1, closeBracket),
                  baseFlags: _kLink | baseFlags,
                ),
              );
              out.add(_Segment(']', 0, marker: true));
              out.add(_Segment('(', 0, marker: true));
              out.add(
                _Segment(
                  input.substring(closeBracket + 2, closeParen),
                  0,
                  marker: true,
                ),
              );
              out.add(_Segment(')', 0, marker: true));
              i = closeParen + 1;
              continue;
            }
          }
        }
      }
      // Bold-italic *** or ___
      if ((i + 2 < n || i + 2 == n - 1) &&
          (input.startsWith('***', i) || input.startsWith('___', i))) {
        final delim = input.substring(i, i + 3);
        final close = input.indexOf(delim, i + 3);
        if (close > i) {
          out.add(_Segment(delim, 0, marker: true));
          out.addAll(
            _parseInline(
              input.substring(i + 3, close),
              baseFlags: baseFlags | _kBold | _kItalic,
            ),
          );
          out.add(_Segment(delim, 0, marker: true));
          i = close + 3;
          continue;
        }
      }
      // Bold ** or __
      if (i + 1 < n &&
          (input.startsWith('**', i) || input.startsWith('__', i))) {
        final delim = input.substring(i, i + 2);
        final close = input.indexOf(delim, i + 2);
        if (close > i) {
          out.add(_Segment(delim, 0, marker: true));
          out.addAll(
            _parseInline(
              input.substring(i + 2, close),
              baseFlags: baseFlags | _kBold,
            ),
          );
          out.add(_Segment(delim, 0, marker: true));
          i = close + 2;
          continue;
        }
      }
      // Strikethrough ~~
      if (i + 1 < n && input.startsWith('~~', i)) {
        final close = input.indexOf('~~', i + 2);
        if (close > i) {
          out.add(_Segment('~~', 0, marker: true));
          out.addAll(
            _parseInline(
              input.substring(i + 2, close),
              baseFlags: baseFlags | _kStrike,
            ),
          );
          out.add(_Segment('~~', 0, marker: true));
          i = close + 2;
          continue;
        }
      }
      // Italic * or _
      if (input[i] == '*' || input[i] == '_') {
        final delim = input[i];
        // avoid matching if next is space?
        final close = input.indexOf(delim, i + 1);
        if (close > i + 1) {
          out.add(_Segment(delim, 0, marker: true));
          out.addAll(
            _parseInline(
              input.substring(i + 1, close),
              baseFlags: baseFlags | _kItalic,
            ),
          );
          out.add(_Segment(delim, 0, marker: true));
          i = close + 1;
          continue;
        }
      }
      // default char
      // accumulate plain text run until special char
      final start = i;
      while (i < n && !_isSpecial(input[i])) {
        i++;
      }
      if (i == start) i++; // progress
      final chunk = input.substring(start, i);
      if (chunk.isNotEmpty) {
        out.add(_Segment(chunk, baseFlags));
      }
    }
    // apply heading level to segments if needed
    if (headingLevel > 0) {
      for (var j = 0; j < out.length; j++) {
        final s = out[j];
        out[j] = _Segment(
          s.text,
          s.flags | _kHeading,
          marker: s.marker,
          headingLevel: headingLevel,
        );
      }
    }
    // baseFlags heading? already passed baseFlags includes _kHeading? In heading line we pass baseFlags _kHeading separately? We set baseFlags: _kHeading. But _parseInline doesn't add heading level except via headingLevel param default 0. We passed headingLevel. Good. But baseFlags includes _kHeading; segments get _kHeading flag. headingLevel set in this call only if headingLevel param >0. Good.
    return out;
  }

  static bool _isSpecial(String c) {
    return c == '`' || c == '*' || c == '_' || c == '[' || c == '~';
  }
}
