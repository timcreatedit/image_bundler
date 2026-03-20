import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_bundler/icon_bundler.dart';
import 'package:sprite_image/sprite_image.dart' as si;

/// This test verifies that an icon rendered via the [si.Sprite] widget looks
/// identical regardless of how many *other* icons are included in the
/// spritesheet.
///
/// The bug: when regenerating a spritesheet with a different number of icons,
/// the grid column count changes (`cols = sqrt(N).ceil()`), which can shift
/// icons to different grid cells. If the generated widget code hardcodes `cols`,
/// or if the rendering pipeline introduces sub-pixel artifacts (due to `.toInt()`
/// truncation, `FilterQuality.medium`, etc.), the goldens will differ.
void main() {
  // Use a single sprite size for the test — 48px is large enough to see
  // artifacts but fast to generate.
  const spriteSize = 48;

  late Directory tempDir;
  late List<File> allInputFiles;

  setUpAll(() {
    // Resolve the example input directory relative to the test file.
    final exampleInputDir = Directory('${Directory.current.path}/../input');
    assert(
      exampleInputDir.existsSync(),
      'Expected example input directory at ${exampleInputDir.path}',
    );
    allInputFiles =
        exampleInputDir
            .listSync()
            .whereType<File>()
            .where(
              (f) => const [
                '.svg',
                '.png',
              ].any((ext) => f.path.toLowerCase().endsWith(ext)),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    assert(
      allInputFiles.length >= 5,
      'Expected at least 5 input icons, found ${allInputFiles.length}',
    );
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spritesheet_stability_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Generates a spritesheet using [files] and returns the path to the
  /// generated sheet PNG for [spriteSize].
  Future<File> generateSheet(List<File> files, Directory outputDir) async {
    final options = IconBundlerOptions(
      name: 'test_icon',
      inputImages: files,
      output: outputDir,
      variants: [spriteSize],
    );

    await for (final _ in bundleIcons(options)) {
      // Consume all events
    }

    final sheetFile = File(
      '${outputDir.path}/assets/test_icon/sheet_$spriteSize.png',
    );
    assert(sheetFile.existsSync(), 'Sheet not generated at ${sheetFile.path}');
    return sheetFile;
  }

  /// Builds a widget that renders a single icon from a spritesheet PNG loaded
  /// as [bytes].
  ///
  /// [iconIndex] is the index of the icon in the sorted sprite list.
  /// [cols] is `sqrt(N).ceil()` where N is the total number of icons.
  Widget buildIconWidget(Uint8List bytes, int iconIndex, int cols) {
    const sizeWithMargin = spriteSize + 2;
    final source = Rect.fromLTWH(
      1.0 + sizeWithMargin * (iconIndex % cols),
      1.0 + sizeWithMargin * (iconIndex ~/ cols),
      spriteSize.toDouble(),
      spriteSize.toDouble(),
    );
    return RepaintBoundary(
      child: Center(
        child: SizedBox(
          width: spriteSize.toDouble(),
          height: spriteSize.toDouble(),
          child: si.Sprite(
            image: MemoryImage(bytes),
            source: source,
            width: spriteSize.toDouble(),
            height: spriteSize.toDouble(),
          ),
        ),
      ),
    );
  }

  /// Pumps the widget and waits for the image to decode.
  ///
  /// Image decoding via [MemoryImage] is async and needs real async
  /// microtask processing. We pump the widget first (in fake-async to build
  /// the tree), then use [tester.runAsync] to let the codec actually decode,
  /// then pump again so the decoded image is painted.
  Future<void> pumpAndWaitForImage(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    // Let the image codec decode in real async
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    // Pump to pick up the decoded image
    await tester.pump();
  }

  testWidgets('icon at index 0 matches between 4-icon and 9-icon sheets', (
    tester,
  ) async {
    // Generate sheets inside runAsync so real I/O (file system, resvg
    // processes) can execute outside the fake-async zone.
    final result = await tester.runAsync(() async {
      final fourFiles = allInputFiles.sublist(0, 4);
      final largeFiles = allInputFiles.toList();

      final fourDir = Directory('${tempDir.path}/four')..createSync();
      final largeDir = Directory('${tempDir.path}/large')..createSync();

      final fourSheet = await generateSheet(fourFiles, fourDir);
      final largeSheet = await generateSheet(largeFiles, largeDir);

      return (
        fourBytes: fourSheet.readAsBytesSync() as Uint8List,
        largeBytes: largeSheet.readAsBytesSync() as Uint8List,
        fourCols: _ceilSqrt(4),
        largeCols: _ceilSqrt(largeFiles.length),
      );
    });

    final fourBytes = result!.fourBytes;
    final largeBytes = result.largeBytes;
    final fourCols = result.fourCols;
    final largeCols = result.largeCols;

    // --- Render icon 0 from the 9-icon sheet ---
    await pumpAndWaitForImage(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: buildIconWidget(largeBytes, 0, largeCols),
      ),
    );

    await expectLater(
      find.byType(si.Sprite),
      matchesGoldenFile('goldens/icon0_from_9icons.png'),
    );

    // --- Render the same icon from the 4-icon sheet ---
    await pumpAndWaitForImage(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: buildIconWidget(fourBytes, 0, fourCols),
      ),
    );

    await expectLater(
      find.byType(si.Sprite),
      matchesGoldenFile('goldens/icon0_from_4icons.png'),
    );

    // --- Compare the two goldens are byte-identical ---
    final golden9 = File(
      '${Directory.current.path}/test/goldens/icon0_from_9icons.png',
    );
    final golden4 = File(
      '${Directory.current.path}/test/goldens/icon0_from_4icons.png',
    );

    expect(
      golden9.existsSync(),
      isTrue,
      reason: 'Golden for 9-icon sheet not found',
    );
    expect(
      golden4.existsSync(),
      isTrue,
      reason: 'Golden for 4-icon sheet not found',
    );

    expect(
      golden9.readAsBytesSync(),
      equals(golden4.readAsBytesSync()),
      reason:
          'The same icon rendered from differently-sized spritesheets should '
          'produce identical output. If this fails, the spritesheet generation '
          'or rendering pipeline is introducing pixel-level differences.',
    );
  });

  testWidgets('icon at index 1 matches between 4-icon and 9-icon sheets', (
    tester,
  ) async {
    final result = await tester.runAsync(() async {
      final fourFiles = allInputFiles.sublist(0, 4);
      final largeFiles = allInputFiles.toList();

      final fourDir = Directory('${tempDir.path}/four')..createSync();
      final largeDir = Directory('${tempDir.path}/large')..createSync();

      final fourSheet = await generateSheet(fourFiles, fourDir);
      final largeSheet = await generateSheet(largeFiles, largeDir);

      return (
        fourBytes: fourSheet.readAsBytesSync() as Uint8List,
        largeBytes: largeSheet.readAsBytesSync() as Uint8List,
        fourCols: _ceilSqrt(4),
        largeCols: _ceilSqrt(largeFiles.length),
      );
    });

    final fourBytes = result!.fourBytes;
    final largeBytes = result.largeBytes;
    final fourCols = result.fourCols;
    final largeCols = result.largeCols;

    // Render icon index 1 from 9-icon sheet
    await pumpAndWaitForImage(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: buildIconWidget(largeBytes, 1, largeCols),
      ),
    );

    await expectLater(
      find.byType(si.Sprite),
      matchesGoldenFile('goldens/icon1_from_9icons.png'),
    );

    // Render icon index 1 from 4-icon sheet
    await pumpAndWaitForImage(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: buildIconWidget(fourBytes, 1, fourCols),
      ),
    );

    await expectLater(
      find.byType(si.Sprite),
      matchesGoldenFile('goldens/icon1_from_4icons.png'),
    );

    // Compare
    final golden9 = File(
      '${Directory.current.path}/test/goldens/icon1_from_9icons.png',
    );
    final golden4 = File(
      '${Directory.current.path}/test/goldens/icon1_from_4icons.png',
    );

    expect(golden9.existsSync(), isTrue);
    expect(golden4.existsSync(), isTrue);

    expect(
      golden9.readAsBytesSync(),
      equals(golden4.readAsBytesSync()),
      reason:
          'Icon at index 1 should look identical regardless of the number of '
          'icons in the spritesheet.',
    );
  });

  // dominos.svg has a non-square viewBox (162.9×163.7), which triggers the
  // .toInt() truncation bug in fitSize(). This test ensures the fix
  // (.round() instead of .toInt()) produces consistent rendering.
  testWidgets(
    'dominos icon (non-square viewBox) matches between 4-icon and 9-icon sheets',
    (tester) async {
      // dominos is at index 2 alphabetically — present in both 4-icon and
      // 9-icon subsets.
      const dominosIndex = 2;

      final result = await tester.runAsync(() async {
        final fourFiles = allInputFiles.sublist(0, 4);
        final largeFiles = allInputFiles.toList();

        final fourDir = Directory('${tempDir.path}/four')..createSync();
        final largeDir = Directory('${tempDir.path}/large')..createSync();

        final fourSheet = await generateSheet(fourFiles, fourDir);
        final largeSheet = await generateSheet(largeFiles, largeDir);

        return (
          fourBytes: fourSheet.readAsBytesSync() as Uint8List,
          largeBytes: largeSheet.readAsBytesSync() as Uint8List,
          fourCols: _ceilSqrt(4),
          largeCols: _ceilSqrt(largeFiles.length),
        );
      });

      final fourBytes = result!.fourBytes;
      final largeBytes = result.largeBytes;
      final fourCols = result.fourCols;
      final largeCols = result.largeCols;

      // Render dominos from 9-icon sheet
      await pumpAndWaitForImage(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: buildIconWidget(largeBytes, dominosIndex, largeCols),
        ),
      );

      await expectLater(
        find.byType(si.Sprite),
        matchesGoldenFile('goldens/dominos_from_9icons.png'),
      );

      // Render dominos from 4-icon sheet
      await pumpAndWaitForImage(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: buildIconWidget(fourBytes, dominosIndex, fourCols),
        ),
      );

      await expectLater(
        find.byType(si.Sprite),
        matchesGoldenFile('goldens/dominos_from_4icons.png'),
      );

      // Compare
      final golden9 = File(
        '${Directory.current.path}/test/goldens/dominos_from_9icons.png',
      );
      final golden4 = File(
        '${Directory.current.path}/test/goldens/dominos_from_4icons.png',
      );

      expect(golden9.existsSync(), isTrue);
      expect(golden4.existsSync(), isTrue);

      expect(
        golden9.readAsBytesSync(),
        equals(golden4.readAsBytesSync()),
        reason:
            'dominos.svg has a non-square viewBox (162.9×163.7) which previously '
            'triggered a .toInt() truncation bug. The icon should look identical '
            'regardless of the total number of icons in the spritesheet.',
      );
    },
  );
}

int _ceilSqrt(int n) {
  var i = 1;
  while (i * i < n) {
    i++;
  }
  return i;
}
