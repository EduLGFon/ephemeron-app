// Lightweight Markdown renderer to widgets. Parses with the GitHub
// flavored set, builds each block once, renders blocks lazily in a
// ListView. Tappable task-list items call [onToggleTask] with the Nth
// task line index in the source.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/platform/system_launcher.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.body, this.onToggleTask});

  final String body;
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context) {
    final doc = md.Document(
      blockSyntaxes: md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      inlineSyntaxes: md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    );
    final nodes = doc.parseLines(body.split('\n'));
    final blocks = _Blocks(context, onToggleTask: onToggleTask);
    for (final n in nodes) {
      n.accept(blocks);
    }
    if (blocks.widgets.isEmpty) {
      return const Text('Nothing to preview');
    }
    return RepaintBoundary(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: blocks.widgets,
      ),
    );
  }
}

class _Blocks implements md.NodeVisitor {
  _Blocks(this.context, {this.onToggleTask});

  final BuildContext context;
  final ValueChanged<int>? onToggleTask;
  final widgets = <Widget>[];
  int listDepth = 0;
  int taskIndex = 0;

  TextStyle get _base =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  @override
  bool visitElementBefore(md.Element element) {
    final tag = element.tag;
    if (tag.startsWith('h')) {
      final level = int.tryParse(tag.substring(1)) ?? 1;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: level == 1 ? 16 : 12, bottom: 4),
          child: Text(
            element.textContent,
            style: _base.copyWith(
              fontSize: 22 - level * 2.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      return false;
    }
    if (tag == 'p') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(text: _spans(element, _base)),
        ),
      );
      return false;
    }
    if (tag == 'ul' || tag == 'ol') {
      listDepth++;
      return true;
    }
    if (tag == 'li') {
      // GitHub-flavored task lists parse to <li class="task-list-item">
      // with an <input type="checkbox"> child; textContent no longer
      // contains the "[ ]" marker, so detect via the input element.
      final children = element.children ?? const <md.Node>[];
      md.Element? checkbox;
      for (final c in children) {
        if (c is md.Element &&
            c.tag == 'input' &&
            c.attributes['type'] == 'checkbox') {
          checkbox = c;
          break;
        }
      }
      final isTask =
          checkbox != null || element.attributes['class'] == 'task-list-item';
      if (isTask) {
        final idx = taskIndex++;
        final checked = checkbox?.attributes.containsKey('checked') ?? false;
        final label = element.textContent.trim();
        widgets.add(
          CheckboxListTile(
            value: checked,
            onChanged: onToggleTask == null ? null : (_) => onToggleTask!(idx),
            title: Text(label.isEmpty ? '(task)' : label),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        );
      } else {
        final text = element.textContent.trim();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: listDepth * 16.0, bottom: 2),
            child: Text('- $text', style: _base),
          ),
        );
      }
      return false;
    }
    if (tag == 'pre') {
      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(bottom: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            element.textContent,
            style: _base.copyWith(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
      return false;
    }
    if (tag == 'blockquote') {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          child: Text(element.textContent, style: _base),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  void visitText(md.Text text) {}

  @override
  void visitElementAfter(md.Element element) {
    if (element.tag == 'ul' || element.tag == 'ol') listDepth--;
  }

  TextSpan _spans(md.Element element, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Text) {
        spans.add(TextSpan(text: child.text, style: base));
      } else if (child is md.Element) {
        final inner = _spans(child, base).children ?? [];
        final style = switch (child.tag) {
          'strong' || 'b' => base.copyWith(fontWeight: FontWeight.bold),
          'em' || 'i' => base.copyWith(fontStyle: FontStyle.italic),
          'code' => base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          'a' => base.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          'del' => base.copyWith(decoration: TextDecoration.lineThrough),
          _ => base,
        };
        if (inner.isEmpty) {
          spans.add(TextSpan(text: child.textContent, style: style));
        } else {
          for (final s in inner) {
            if (s is TextSpan) {
              spans.add(
                TextSpan(text: s.text, style: (s.style ?? base).merge(style)),
              );
            } else {
              spans.add(s);
            }
          }
        }
        if (child.tag == 'a' && child.attributes['href'] != null) {
          final url = child.attributes['href']!;
          spans.add(
            TextSpan(
              text: ' ($url)',
              style: base.copyWith(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  SystemLauncher.openUrl(url);
                },
            ),
          );
        }
      }
    }
    return TextSpan(children: spans, style: base);
  }
}

/// Word and character counts for the editor status line.
({int words, int chars}) countWords(String text) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return (words: words, chars: text.length);
}
