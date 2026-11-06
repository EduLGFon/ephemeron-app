// Part of the habits screen library: the 7-day selected-day strip.
part of '../habits_screen.dart';

class _DayStrip extends StatefulWidget {
  const _DayStrip({required this.selected, required this.onSelect});

  final String selected;
  final void Function(String day) onSelect;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final d in days) ...[
            ChoiceChip(
              label: Text('${DeviceDateFormat.e(context).format(d)} ${d.day}'),
              selected: habitDateKey(d) == widget.selected,
              onSelected: (_) => widget.onSelect(habitDateKey(d)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
