import 'package:ephemeron/core/time/picker_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePickerDate', () {
    final fallback = DateTime(2026, 1, 15);

    test('prefers current field value', () {
      final result = resolvePickerDate(
        current: '2026-05-20',
        remembered: '2026-06-01',
        fallback: fallback,
      );
      expect(result, DateTime(2026, 5, 20));
    });

    test('uses remembered when current is unset', () {
      final result = resolvePickerDate(
        current: null,
        remembered: '2026-06-01',
        fallback: fallback,
      );
      expect(result, DateTime(2026, 6, 1));
    });

    test('uses fallback when current and remembered are unset', () {
      final result = resolvePickerDate(
        current: null,
        remembered: null,
        fallback: fallback,
      );
      expect(result, DateTime(2026, 1, 15));
    });

    test('ignores invalid current and falls back to remembered', () {
      final result = resolvePickerDate(
        current: 'not-a-date',
        remembered: '2026-06-01',
        fallback: fallback,
      );
      expect(result, DateTime(2026, 6, 1));
    });
  });

  group('resolvePickerTimeMinutes', () {
    test('prefers current minutes', () {
      final result = resolvePickerTimeMinutes(
        currentMinutes: 615,
        rememberedHhmm: '08:00',
        fallbackMinutes: 540,
      );
      expect(result, 615);
    });

    test('uses remembered HH:mm when current is unset', () {
      final result = resolvePickerTimeMinutes(
        currentMinutes: null,
        rememberedHhmm: '08:30',
        fallbackMinutes: 540,
      );
      expect(result, 510);
    });

    test('uses fallback when unset and no remembered value', () {
      final result = resolvePickerTimeMinutes(
        currentMinutes: null,
        rememberedHhmm: null,
        fallbackMinutes: 540,
      );
      expect(result, 540);
    });

    test('ignores invalid remembered value', () {
      final result = resolvePickerTimeMinutes(
        currentMinutes: null,
        rememberedHhmm: 'bad',
        fallbackMinutes: 540,
      );
      expect(result, 540);
    });
  });

  group('resolvePickerDateTime', () {
    final fallback = DateTime(2026, 1, 15, 9, 0);

    test('prefers current ISO value', () {
      final result = resolvePickerDateTime(
        currentIso: '2026-05-20T14:30',
        rememberedIso: '2026-06-01T08:00',
        fallback: fallback,
      );
      expect(result, DateTime.parse('2026-05-20T14:30'));
    });

    test('uses remembered when current is unset', () {
      final result = resolvePickerDateTime(
        currentIso: null,
        rememberedIso: '2026-06-01T08:00',
        fallback: fallback,
      );
      expect(result, DateTime.parse('2026-06-01T08:00'));
    });

    test('uses fallback when nothing is set', () {
      final result = resolvePickerDateTime(
        currentIso: null,
        rememberedIso: null,
        fallback: fallback,
      );
      expect(result, fallback);
    });
  });

  group('format helpers', () {
    test('formatHhmm zero-pads', () {
      expect(formatHhmm(9, 5), '09:05');
    });

    test('formatYmd zero-pads', () {
      expect(formatYmd(DateTime(2026, 3, 7)), '2026-03-07');
    });

    test('parseHhmm rejects invalid values', () {
      expect(parseHhmm(null), isNull);
      expect(parseHhmm(''), isNull);
      expect(parseHhmm('25:00'), isNull);
      expect(parseHhmm('09:60'), isNull);
      expect(parseHhmm('abc'), isNull);
    });
  });
}
