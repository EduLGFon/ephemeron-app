// Generates test/all_test.dart, the single entrypoint for the whole unit and
// widget suite.
//
// Why: `flutter test` emits a fresh kernel for every test file and compiles
// them through one serial queue, so wall time grows with the number of files
// even when the tests themselves are fast. Importing every case into one
// entrypoint makes the run pay a single compile.
//
// Run from app/: dart run tools/gen_test_runner.dart
import 'dart:io';

const _casesDir = 'test/cases';
const _outFile = 'test/all_test.dart';

void main() {
  final files =
      Directory(_casesDir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.endsWith('_case.dart'))
          .toList()
        ..sort();
  if (files.isEmpty) {
    stderr.writeln('No *_case.dart files found in $_casesDir.');
    exit(1);
  }

  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Run: dart run tools/gen_test_runner.dart')
    ..writeln('//')
    ..writeln(
      '// One entrypoint for every case file. Flutter compiles one kernel per',
    )
    ..writeln(
      '// test file, so keeping the suite in a single file removes that cost.',
    )
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln();

  for (final name in files) {
    out.writeln("import 'cases/$name' as ${_alias(name)};");
  }

  out
    ..writeln()
    ..writeln('const _included = <String>{');
  for (final name in files) {
    out.writeln("  '$name',");
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('void main() {')
    ..writeln("  test('test runner includes every case file', () {")
    ..writeln('    expect(_caseFilesOnDisk(), _included,')
    ..writeln('        reason: \'test/all_test.dart is stale. Run: \'')
    ..writeln("            'dart run tools/gen_test_runner.dart');")
    ..writeln('  });')
    ..writeln();

  for (final name in files) {
    out.writeln("  group('${_alias(name)}', ${_alias(name)}.main);");
  }
  out
    ..writeln('}')
    ..writeln()
    ..writeln('Set<String> _caseFilesOnDisk() {')
    ..writeln("  final cases = Directory('$_casesDir')")
    ..writeln('      .listSync()')
    ..writeln('      .whereType<File>()')
    ..writeln('      .map((f) => f.uri.pathSegments.last)')
    ..writeln("      .where((name) => name.endsWith('_case.dart'))")
    ..writeln('      .toSet();')
    ..writeln("  final stray = Directory('test')")
    ..writeln('      .listSync(recursive: true)')
    ..writeln('      .whereType<File>()')
    ..writeln('      .map((f) => f.path.replaceAll(r\'\\\', \'/\'))')
    ..writeln("      .where((path) => path.endsWith('_test.dart'))")
    ..writeln("      .where((path) => !path.endsWith('/all_test.dart'))")
    ..writeln('      .toSet();')
    ..writeln('  expect(stray, isEmpty,')
    ..writeln("      reason: 'Move top-level test files under test/cases/ as '")
    ..writeln("          '*_case.dart and regenerate this runner.');")
    ..writeln('  return cases;')
    ..writeln('}');

  File(_outFile).writeAsStringSync(out.toString());
  stdout.writeln('Wrote $_outFile with ${files.length} case files.');
}

String _alias(String fileName) =>
    fileName.substring(0, fileName.length - '_case.dart'.length);
