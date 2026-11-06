part of '../timeline_chrome.dart';

class TimelineHourGutter extends StatelessWidget {
  const TimelineHourGutter({
    super.key,
    required this.hourHeight,
    required this.width,
  });

  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 24 * hourHeight,
      child: Stack(
        children: [
          for (var h = 0; h < 24; h++)
            Positioned(
              top: h * hourHeight - 7,
              right: 4,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}
