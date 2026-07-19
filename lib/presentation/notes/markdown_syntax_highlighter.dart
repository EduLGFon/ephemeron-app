import 'package:flutter/material.dart';

class MarkdownSyntaxHighlighter extends TextEditingController {
  MarkdownSyntaxHighlighter({super.text});

  bool toggleCheckboxAtCursor() {
    final offset = selection.baseOffset;
    if (offset < 0) return false;

    final textBefore = text.substring(0, offset);
    final textAfter = text.substring(offset);
    final lineStart = textBefore.lastIndexOf('\n') + 1;
    final lineEndIndex = textAfter.indexOf('\n');
    final lineEnd = lineEndIndex == -1 ? text.length : offset + lineEndIndex;

    if (lineStart >= lineEnd) return false;

    final line = text.substring(lineStart, lineEnd);
    final match = RegExp(r'^(\s*(?:-\s)?)(\[[ x]\])(\s)').firstMatch(line);
    
    if (match != null) {
      final checkboxStart = lineStart + match.start;
      final checkboxEnd = lineStart + match.end;

      if (offset >= checkboxStart && offset <= checkboxEnd) {
        final isChecked = match.group(2)!.contains('x');
        final newChar = isChecked ? ' ' : 'x';
        final replaceStart = lineStart + match.start + match.group(1)!.length + 1;
        
        final newText = text.replaceRange(replaceStart, replaceStart + 1, newChar);
        
        value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: offset),
        );
        return true;
      }
    }
    return false;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> spans = [];
    final pattern = RegExp(
      r'(?<bold>\*\*(?<boldContent>.*?)\*\*)|(?<italic>_(?<italicContent>.*?)_|\*(?<italicContent2>.*?)\*)|(?<heading>(?<headingSyntax>#{1,6}\s)(?<headingContent>.*))|(?<checkbox>^\s*(?:-\s)?\[[ x]\]\s)|(?<list>^\s*[-*]\s.*|^\s*\d+\.\s.*)|(?<link>\[(?<linkContent>.*?)\]\((?<linkUrl>.*?)\))',
      multiLine: true,
    );

    int activeLineStart = -1;
    int activeLineEnd = -1;
    if (selection.isValid && selection.isCollapsed) {
      final offset = selection.baseOffset;
      activeLineStart = text.lastIndexOf('\n', offset - 1 == -1 ? 0 : offset - 1) + 1;
      final end = text.indexOf('\n', offset);
      activeLineEnd = end == -1 ? text.length : end;
    } else if (selection.isValid && !selection.isCollapsed) {
      activeLineStart = text.lastIndexOf('\n', selection.start - 1 == -1 ? 0 : selection.start - 1) + 1;
      final end = text.indexOf('\n', selection.end);
      activeLineEnd = end == -1 ? text.length : end;
    }

    int lastMatchEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      final touchesActiveLine = (match.start <= activeLineEnd && match.end >= activeLineStart);
      final hideSyntax = !touchesActiveLine;
      final hiddenStyle = style?.copyWith(color: Colors.transparent, fontSize: 0.0);

      if (match.namedGroup('bold') != null) {
        final content = match.namedGroup('boldContent')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(fontWeight: FontWeight.bold);

        spans.add(TextSpan(text: '**', style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
        spans.add(TextSpan(text: '**', style: syntaxStyle));
      } else if (match.namedGroup('italic') != null) {
        final content = match.namedGroup('italicContent') ?? match.namedGroup('italicContent2')!;
        final syntaxChar = match.namedGroup('italicContent') != null ? '_' : '*';
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(fontStyle: FontStyle.italic);

        spans.add(TextSpan(text: syntaxChar, style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
        spans.add(TextSpan(text: syntaxChar, style: syntaxStyle));
      } else if (match.namedGroup('heading') != null) {
        final syntax = match.namedGroup('headingSyntax')!;
        final content = match.namedGroup('headingContent')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey, fontSize: (style.fontSize ?? 14) * 1.3);
        final contentStyle = style?.copyWith(fontWeight: FontWeight.bold, fontSize: (style.fontSize ?? 14) * 1.3);

        spans.add(TextSpan(text: syntax, style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
      } else if (match.namedGroup('checkbox') != null) {
        final matchText = text.substring(match.start, match.end);
        final isChecked = matchText.contains('[x]');
        
        final innerMatch = RegExp(r'^(\s*(?:-\s)?)(\[[ x]\])(\s)$').firstMatch(matchText);
        if (innerMatch != null) {
          final prefix = innerMatch.group(1)!;
          final suffix = innerMatch.group(3)!;
          
          if (prefix.isNotEmpty) {
            spans.add(TextSpan(text: prefix, style: hiddenStyle));
          }
          
          spans.add(TextSpan(text: '[', style: hiddenStyle));
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
              size: (style?.fontSize ?? 14) + 6,
              color: isChecked ? Colors.grey : Colors.blueAccent,
            ),
          ));
          spans.add(TextSpan(text: ']', style: hiddenStyle));
          
          if (suffix.isNotEmpty) {
            spans.add(TextSpan(text: suffix, style: style));
          }
        }
      } else if (match.namedGroup('list') != null) {
        final matchText = text.substring(match.start, match.end);
        final innerMatch = RegExp(r'^(\s*)([-*]\s|\d+\.\s)(.*)$').firstMatch(matchText);
        if (innerMatch != null) {
          final indent = innerMatch.group(1)!;
          final bullet = innerMatch.group(2)!;
          final content = innerMatch.group(3)!;
          
          if (indent.isNotEmpty) {
            spans.add(TextSpan(text: indent, style: style));
          }
          
          if (bullet.trim() == '-' || bullet.trim() == '*') {
            spans.add(TextSpan(text: bullet[0], style: hiddenStyle));
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Icon(Icons.circle, size: (style?.fontSize ?? 14) * 0.4, color: style?.color?.withValues(alpha: 0.7) ?? Colors.grey),
              ),
            ));
          } else {
            spans.add(TextSpan(text: bullet, style: style?.copyWith(fontWeight: FontWeight.bold, color: Colors.blueAccent)));
          }
          
          spans.add(TextSpan(text: content, style: style));
        }
      } else if (match.namedGroup('link') != null) {
        final linkContent = match.namedGroup('linkContent')!;
        final linkUrl = match.namedGroup('linkUrl')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(color: Colors.blue, decoration: TextDecoration.underline);

        spans.add(TextSpan(text: '[', style: syntaxStyle));
        spans.add(TextSpan(text: linkContent, style: contentStyle));
        spans.add(TextSpan(text: ']($linkUrl)', style: syntaxStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: style,
      ));
    }

    return TextSpan(style: style, children: spans);
  }
}
