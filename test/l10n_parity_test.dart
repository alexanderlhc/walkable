import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Safety net for the ARB files under lib/l10n: every locale must define
/// exactly the same message keys, and every placeholder declared in the
/// template's @key metadata must actually appear in each translation.
/// Catches the classic "added a string to app_en.arb, forgot app_da.arb"
/// drift before it becomes a runtime MissingTranslation.
void main() {
  // `flutter test` runs from the package root, so the ARB directory resolves
  // relative to the current directory.
  final l10nDir = Directory('lib/l10n');
  const templateFileName = 'app_en.arb';

  /// Locale name -> decoded ARB content, keyed by file basename sans prefix.
  late final Map<String, Map<String, dynamic>> arbs;

  /// The translatable message keys of one ARB file: everything except the
  /// `@@locale` entry and `@key` metadata entries.
  Set<String> messageKeys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  setUpAll(() {
    expect(l10nDir.existsSync(), isTrue,
        reason: 'Expected ${l10nDir.path} to exist relative to the package '
            'root (cwd: ${Directory.current.path})');

    final arbFiles = l10nDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();

    arbs = {
      for (final file in arbFiles)
        file.uri.pathSegments.last:
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    };
  });

  test('there are at least two ARB locales to compare', () {
    expect(arbs.keys, contains(templateFileName));
    expect(arbs.length, greaterThanOrEqualTo(2),
        reason: 'Expected the template plus at least one translation in '
            '${l10nDir.path}; found only: ${arbs.keys.toList()..sort()}');
  });

  test('all locales define the same message key set', () {
    final template = arbs[templateFileName]!;
    final templateKeys = messageKeys(template);

    final failures = <String>[];
    for (final entry in arbs.entries) {
      if (entry.key == templateFileName) continue;

      final localeKeys = messageKeys(entry.value);
      final missing = templateKeys.difference(localeKeys).toList()..sort();
      final extra = localeKeys.difference(templateKeys).toList()..sort();

      if (missing.isNotEmpty) {
        failures.add('${entry.key} is missing keys defined in '
            '$templateFileName: $missing');
      }
      if (extra.isNotEmpty) {
        failures.add('${entry.key} has extra keys not defined in '
            '$templateFileName: $extra');
      }
    }

    if (failures.isNotEmpty) {
      fail('Locale key sets differ:\n${failures.join('\n')}');
    }
  });

  test('placeholders declared in the template metadata appear in every locale',
      () {
    final template = arbs[templateFileName]!;
    // Placeholder references in a message body look like {name}.
    final placeholderRef = RegExp(r'\{(\w+)\}');

    final failures = <String>[];
    for (final key in messageKeys(template)) {
      final metadata = template['@$key'];
      if (metadata is! Map<String, dynamic>) continue;
      final placeholders = metadata['placeholders'];
      if (placeholders is! Map<String, dynamic>) continue;

      final declared = placeholders.keys.toSet();

      for (final entry in arbs.entries) {
        final message = entry.value[key];
        if (message is! String) continue; // Missing key: parity test reports.

        final used =
            placeholderRef.allMatches(message).map((m) => m.group(1)!).toSet();

        final unused = declared.difference(used).toList()..sort();
        final undeclared = used.difference(declared).toList()..sort();
        if (unused.isNotEmpty) {
          failures.add('${entry.key}: "$key" never references declared '
              'placeholder(s) $unused');
        }
        if (undeclared.isNotEmpty) {
          failures.add('${entry.key}: "$key" references placeholder(s) '
              '$undeclared not declared in the $templateFileName metadata');
        }
      }
    }

    if (failures.isNotEmpty) {
      fail('Placeholder usage differs from template metadata:\n'
          '${failures.join('\n')}');
    }
  });
}
