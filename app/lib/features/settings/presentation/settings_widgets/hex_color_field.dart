part of '../settings_widgets.dart';

class HexColorFieldTile extends StatelessWidget {
  const HexColorFieldTile({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.fieldKey,
    required this.onSubmitted,
  });

  final String title;
  final String help;
  final String value;
  final Key fieldKey;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          HexColorField(
            fieldKey: fieldKey,
            value: value,
            onSubmitted: onSubmitted,
          ),
        ],
      ),
    );
  }
}

class HexColorField extends StatefulWidget {
  const HexColorField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.fieldKey,
  });

  final String value;
  final ValueChanged<String> onSubmitted;
  final Key? fieldKey;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (!isValidHex(raw)) {
      setState(() => _error = 'Enter a valid hex like #RRGGBB.');
      return;
    }
    setState(() => _error = null);
    final normalized = raw.startsWith('#') ? raw : '#$raw';
    _controller.text = normalized;
    widget.onSubmitted(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      autocorrect: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: '#RRGGBB',
        errorText: _error,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
