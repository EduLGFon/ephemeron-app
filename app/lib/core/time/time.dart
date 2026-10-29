// Date/time helpers. Timed items: UTC epoch ms + IANA zone id.
// All-day items: 'YYYY-MM-DD' local date strings (never timestamps).

String dateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

int epochMs(DateTime utc) => utc.toUtc().millisecondsSinceEpoch;
