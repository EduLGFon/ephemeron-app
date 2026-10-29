// Lightweight Markdown renderer: parses with package:markdown and builds
// TextSpans directly (no webview, no heavy widget tree). Preview is parsed
// once per body version and cached; long notes render in block chunks so
// the first paint stays fast. Tappable checklist items toggle the source
// via [onToggleTask].
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    super.key,
    required this.body,
    this.onToggleTask,
    this.maxBlocks,
  });

  final String body;
  final void Function(int lineIndex, bool checked)? onToggleTask;
  final int? maxBlocks;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  late String _parsedFor;
  late List<md.Node> _nodes;

  @override
  void initState() {
    super.initState();
    _parsedFor = widget.body;
    _nodes = _parse(widget.body);
  }

  static List<md.Node> _parse(String body) {
    final doc = md.Document(
      blockSyntaxes: md.BlockSyntax.list,
      inlineSyntaxes: md.InlineSyntax.list,
    );
    return doc.parse(body);
  }

  @override
  void didUpdateWidget(MarkdownPreview old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body) {
      _parsedFor = widget.body;
      _nodes = _parse(widget.body);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = widget.maxBlocks == null
        ? _nodes
        : _nodes.take(widget.maxBlocks!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _Block(
            node: nodes[i],
            theme: theme,
            onToggleTask: widget.onToggleTask,
          ),
        if (widget.maxBlocks != null && _nodes.length > widget.maxBlocks!)
          Text(
            '+ ${_nodes.length - widget.maxBlocks!} more blocks',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(
      {required this.node, required this.theme, this.onToggleTask});

  final md.Node node;
  final ThemeData theme;
  final void Function(int lineIndex, bool checked)? onToggleTask;

  @override
  Widget build(BuildContext context) {
    final n = node;
    if (n is md.Element) {
      switch (n.tag) {
        case 'h1':
        case 'h2':
        case 'h3':
          final level = int.parse(n.tag.substring(1));
          final size = [0.0, 22.0, 19.0, 17.0][level.clamp(1, 3)];
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text.rich(
              _spans(n.children, theme.textTheme.bodyLarge!.copyWith(
                fontSize: size,
                fontWeight: FontWeight.bold,
              )),
            ),
          );
        case 'p':
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(_spans(
                n.children, theme.textTheme.bodyMedium!)),
          );
        case 'ul':
        case 'ol':
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < (n.children?.length ?? 0); i++)
                  _listItem(n.children![i] as md.Element,
                      ordered: n.tag == 'ol', index: i),
              ],
            ),
          );
        case 'blockquote':
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(
                      color: theme.colorScheme.primary, width: 3)),
            ),
            child: Text.rich(_spans(
                n.children, theme.textTheme.bodyMedium!)),
          );
        case 'pre':
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: SelectableText(
              n.textContent,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          );
        case 'hr':
          return const Divider();
      }
    }
    return const SizedBox.shrink();
  }

  Widget _listItem(md.Element li,
      {required bool ordered, required int index}) {
    final text = li.textContent;
    final task = RegExp(r'^\s*\[( |x|X)\]\s').firstMatch(text);
    if (task != null) {
      final checked = task.group(1)!.toLowerCase() == 'x';
      final rest = text.substring(task.end);
      return InkWell(
        onTap: onToggleTask == null
            ? null
            : () => onToggleTask!(li.hashCode, !checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                checked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rest,
                  style: TextStyle(
                    decoration:
                        checked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final bullet = ordered ? '${index + 1}. ' : '- ';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(TextSpan(
        text: bullet,
        children: [
          _spans(li.children, const TextStyle(fontSize: 14)),
        ],
      )),
    );
  }

  TextSpan _spans(List<md.Node>? children, TextStyle base) {
    return TextSpan(
      style: base,
      children: [
        for (final c in children ?? const <md.Node>[])
          _span(c, base),
      ],
    );
  }

  TextSpan _span(md.Node n, TextStyle base) {
    if (n is md.Text) return TextSpan(text: n.text, style: base);
    if (n is md.Element) {
      switch (n.tag) {
        case 'strong':
        case 'b':
          return TextSpan(
            style: base.copyWith(fontWeight: FontWeight.bold),
            children: [
              for (final c in n.children ?? const <md.Node>[])
                _span(c, base),
            ],
          );
        case 'em':
        case 'i':
          return TextSpan(
            style:
                base.copyWith(fontStyle: FontStyle.fontStyle),
            children: [
              for (final c in n.children ?? const <md.Node>[])
                _span(c, base),
            ],
          );
        case 'code':
          return TextSpan(
            text: n.textContent,
            style: base.copyWith(fontFamily: 'monospace'),
          );
        case 'a':
          return TextSpan(
            text: n.textContent,
            style: base.copyWith(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {},
          );
      }
      return TextSpan(
        children: [
          for (final c in n.children ?? const <md.Node>[])
            _span(c, base),
        ],
        style: base,
      );
    }
    return const TextSpan();
  }
}
