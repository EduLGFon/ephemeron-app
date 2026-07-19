import 'package:flutter/material.dart';

class MarkdownSyntaxHighlighter extends TextEditingController {
  MarkdownSyntaxHighlighter({super.text, this.showReorderArrows = false});

  bool showReorderArrows;

  bool _moveLineUp(int lineStart, int lineEnd) {
    if (lineStart == 0) return false;
    final currentLine = text.substring(lineStart, lineEnd);
    final previousLineStart = text.lastIndexOf('\n', lineStart - 2) + 1;
    final previousLine = text.substring(previousLineStart, lineStart - 1);
    
    final newText = text.replaceRange(previousLineStart, lineEnd, '$currentLine\n$previousLine');
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: previousLineStart + (selection.baseOffset - lineStart)),
    );
    return true;
  }

  bool _moveLineDown(int lineStart, int lineEnd) {
    if (lineEnd == text.length) return false;
    final currentLine = text.substring(lineStart, lineEnd);
    final nextLineEndIndex = text.indexOf('\n', lineEnd + 1);
    final nextLineEnd = nextLineEndIndex == -1 ? text.length : nextLineEndIndex;
    final nextLine = text.substring(lineEnd + 1, nextLineEnd);
    
    final newText = text.replaceRange(lineStart, nextLineEnd, '$nextLine\n$currentLine');
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + nextLine.length + 1 + (selection.baseOffset - lineStart)),
    );
    return true;
  }

  bool handleTapAtCursor() {
    final offset = selection.baseOffset;
    if (offset < 0) return false;

    final textBefore = text.substring(0, offset);
    final textAfter = text.substring(offset);
    final lineStart = textBefore.lastIndexOf('\n') + 1;
    final lineEndIndex = textAfter.indexOf('\n');
    final lineEnd = lineEndIndex == -1 ? text.length : offset + lineEndIndex;

    if (lineStart >= lineEnd) return false;
    final line = text.substring(lineStart, lineEnd);

    final checkboxMatch = RegExp(r'^(\s*)(-\s)?(\[[ x]\])(\s)').firstMatch(line);
    if (checkboxMatch != null) {
      final indent = checkboxMatch.group(1)!;
      final dash = checkboxMatch.group(2);
      
      final contentStart = lineStart + indent.length;
      final localOffset = offset - contentStart;
      
      bool isUp = false;
      bool isDown = false;
      bool isCheck = false;
      
      if (showReorderArrows) {
        if (dash != null) {
          if (localOffset == 0) { isUp = true; }
          else if (localOffset == 1 || localOffset == 2) { isDown = true; }
          else if (localOffset >= 3 && localOffset <= 5) { isCheck = true; }
        } else {
          if (localOffset == 0) { isUp = true; }
          else if (localOffset == 1) { isDown = true; }
          else if (localOffset >= 2 && localOffset <= 4) { isCheck = true; }
        }
      } else {
        if (dash != null) {
          if (localOffset >= 2 && localOffset <= 4) { isCheck = true; }
        } else {
          if (localOffset >= 0 && localOffset <= 2) { isCheck = true; }
        }
      }
      
      if (isUp) return _moveLineUp(lineStart, lineEnd);
      if (isDown) return _moveLineDown(lineStart, lineEnd);
      if (isCheck) {
        final isChecked = checkboxMatch.group(3)!.contains('x');
        final newChar = isChecked ? ' ' : 'x';
        final replaceStart = contentStart + (dash?.length ?? 0) + 1;
        final newText = text.replaceRange(replaceStart, replaceStart + 1, newChar);
        value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: offset));
        return true;
      }
      return false;
    }

    if (showReorderArrows) {
      final listMatch = RegExp(r'^(\s*)([-*]\s|\d+\.\s)').firstMatch(line);
      if (listMatch != null) {
        final indent = listMatch.group(1)!;
        final bullet = listMatch.group(2)!;
        
        final contentStart = lineStart + indent.length;
        final localOffset = offset - contentStart;
        
        bool isUp = false;
        bool isDown = false;
        
        if (bullet.trim() == '-' || bullet.trim() == '*') {
          if (localOffset == 0) { isUp = true; }
          else if (localOffset == 1 || localOffset == 2) { isDown = true; }
          
          if (isUp) return _moveLineUp(lineStart, lineEnd);
          if (isDown) return _moveLineDown(lineStart, lineEnd);
        }
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
        
        final innerMatch = RegExp(r'^(\s*)(-\s)?(\[[ x]\])(\s)$').firstMatch(matchText);
        if (innerMatch != null) {
          final indent = innerMatch.group(1)!;
          final dash = innerMatch.group(2);
          final suffix = innerMatch.group(4)!;
          
          if (indent.isNotEmpty) spans.add(TextSpan(text: indent, style: style));

          WidgetSpan checkboxIcon = WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Icon(
                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                size: (style?.fontSize ?? 14) + 6,
                color: isChecked ? Colors.grey : Colors.blueAccent,
              ),
            ),
          );

          if (showReorderArrows) {
            WidgetSpan upArrow = WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.arrow_upward, size: 16, color: Colors.grey.withValues(alpha: 0.6)),
            );
            WidgetSpan downArrow = WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.arrow_downward, size: 16, color: Colors.grey.withValues(alpha: 0.6)),
            );
            
            if (dash != null) {
              spans.add(upArrow);
              spans.add(downArrow);
              spans.add(TextSpan(text: '[', style: hiddenStyle));
              spans.add(checkboxIcon);
              spans.add(TextSpan(text: ']', style: hiddenStyle));
            } else {
              spans.add(upArrow);
              spans.add(downArrow);
              spans.add(checkboxIcon);
            }
          } else {
            if (dash != null) {
              spans.add(TextSpan(text: dash, style: hiddenStyle));
            }
            spans.add(TextSpan(text: '[', style: hiddenStyle));
            spans.add(checkboxIcon);
            spans.add(TextSpan(text: ']', style: hiddenStyle));
          }
          
          if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix, style: style));
        }
      } else if (match.namedGroup('list') != null) {
        final matchText = text.substring(match.start, match.end);
        final innerMatch = RegExp(r'^(\s*)([-*]\s|\d+\.\s)(.*)$').firstMatch(matchText);
        if (innerMatch != null) {
          final indent = innerMatch.group(1)!;
          final bullet = innerMatch.group(2)!;
          final content = innerMatch.group(3)!;
          
          if (indent.isNotEmpty) spans.add(TextSpan(text: indent, style: style));
          
          if (bullet.trim() == '-' || bullet.trim() == '*') {
            if (showReorderArrows) {
              WidgetSpan upArrow = WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.arrow_upward, size: 16, color: Colors.grey.withValues(alpha: 0.6)),
              );
              WidgetSpan downAndBullet = WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward, size: 16, color: Colors.grey.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Icon(Icons.circle, size: (style?.fontSize ?? 14) * 0.4, color: style?.color?.withValues(alpha: 0.7) ?? Colors.grey),
                    const SizedBox(width: 4),
                  ],
                ),
              );
              spans.add(upArrow);
              spans.add(downAndBullet);
            } else {
              spans.add(TextSpan(text: bullet[0], style: hiddenStyle));
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(Icons.circle, size: (style?.fontSize ?? 14) * 0.4, color: style?.color?.withValues(alpha: 0.7) ?? Colors.grey),
                ),
              ));
            }
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
