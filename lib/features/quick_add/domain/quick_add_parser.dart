/// Result of parsing a quick-add title like "take meds #health ~personal -p4"
/// into its structured parts. [cleanTitle] has every recognized token
/// removed, so what's left is what actually becomes the task/event title.
class QuickAddParseResult {
  const QuickAddParseResult({
    required this.cleanTitle,
    this.tagName,
    this.listName,
    this.priority,
  });

  final String cleanTitle;
  final String? tagName;
  final String? listName;

  /// Already mapped to this app's internal 0-3 scale (0 = none ... 3 =
  /// high) — the shorthand's `-p1`..`-p4` is 1-indexed to match the
  /// brainstorm's own example ("-p4" for a fairly urgent task), so this
  /// is `parsedNumber - 1`, not the raw digit.
  final int? priority;
}

class QuickAddParser {
  const QuickAddParser._();

  static final _tagPattern = RegExp(r'(?:^|\s)#(\w+)');
  static final _listPattern = RegExp(r'(?:^|\s)~(\w+)');
  static final _priorityPattern = RegExp(r'(?:^|\s)-p([1-4])\b');

  static QuickAddParseResult parse(String input) {
    var remaining = input;
    String? tagName;
    String? listName;
    int? priority;

    final tagMatch = _tagPattern.firstMatch(remaining);
    if (tagMatch != null) {
      tagName = tagMatch.group(1);
      remaining = remaining.replaceRange(tagMatch.start, tagMatch.end, '');
    }

    final listMatch = _listPattern.firstMatch(remaining);
    if (listMatch != null) {
      listName = listMatch.group(1);
      remaining = remaining.replaceRange(listMatch.start, listMatch.end, '');
    }

    final priorityMatch = _priorityPattern.firstMatch(remaining);
    if (priorityMatch != null) {
      priority = int.parse(priorityMatch.group(1)!) - 1;
      remaining = remaining.replaceRange(priorityMatch.start, priorityMatch.end, '');
    }

    final cleanTitle = remaining.replaceAll(RegExp(r'\s+'), ' ').trim();

    return QuickAddParseResult(
      cleanTitle: cleanTitle,
      tagName: tagName,
      listName: listName,
      priority: priority,
    );
  }
}
