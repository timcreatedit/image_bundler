import 'dart:io';
import 'dart:math';

import 'package:icon_bundler/src/spritesheet.dart';
import 'package:icon_bundler/src/renderer.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

/// Extracts the pixel region for a given icon from a spritesheet PNG.
///
/// The layout is a grid with 1px margin around each cell:
///   left = (index % cols) * (spriteSize + 2) + 1
///   top  = (index ~/ cols) * (spriteSize + 2) + 1
///   width = height = spriteSize
Image extractIconRegion(Image sheet, int index, int cols, int spriteSize) {
  final margin = 1;
  final effectiveWidth = spriteSize + 2 * margin;
  final left = (index % cols) * effectiveWidth + margin;
  final top = (index ~/ cols) * effectiveWidth + margin;
  return copyCrop(
    sheet,
    x: left,
    y: top,
    width: spriteSize,
    height: spriteSize,
  );
}

/// Compares two images pixel-by-pixel. Returns true if identical.
bool imagesAreIdentical(Image a, Image b) {
  if (a.width != b.width || a.height != b.height) return false;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (a.getPixel(x, y) != b.getPixel(x, y)) return false;
    }
  }
  return true;
}

/// Returns the number of pixels that differ between two same-sized images.
int countDifferingPixels(Image a, Image b) {
  assert(a.width == b.width && a.height == b.height);
  var count = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (a.getPixel(x, y) != b.getPixel(x, y)) count++;
    }
  }
  return count;
}

void main() {
  final inputDir = Directory('example/input');

  // All image files in the example input directory, sorted by name.
  late List<File> allFiles;

  setUpAll(() {
    final supportedExts = {'.svg', '.png', '.jpg', '.jpeg'};
    allFiles =
        inputDir
            .listSync()
            .whereType<File>()
            .where(
              (f) => supportedExts.contains(
                f.path.substring(f.path.lastIndexOf('.')).toLowerCase(),
              ),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    // Sanity: we need at least 5 files to make the test meaningful.
    expect(allFiles.length, greaterThanOrEqualTo(5));
  });

  test(
    'icon pixel content is identical across spritesheets with different icon counts',
    () async {
      const spriteSize = 24;

      // --- Sheet A: use a small subset (first 3 SVGs) ---
      final subsetFiles = allFiles.sublist(0, 3);
      final sheetA = await Spritesheet.fromFiles(
        files: subsetFiles,
        spriteSize: spriteSize,
      );
      final rendererA = SpritesheetRenderer();
      final bytesA = await rendererA.render(sheetA);
      final imageA = decodePng(bytesA)!;

      // --- Sheet B: use all SVG files ---
      final sheetB = await Spritesheet.fromFiles(
        files: allFiles,
        spriteSize: spriteSize,
      );
      final rendererB = SpritesheetRenderer();
      final bytesB = await rendererB.render(sheetB);
      final imageB = decodePng(bytesB)!;

      // The two sheets should have different column counts to make the test
      // meaningful — the grid layout must actually differ.
      expect(
        sheetA.cols,
        isNot(equals(sheetB.cols)),
        reason: 'Test requires different column counts between sheets',
      );

      // For each icon in the subset, extract its region from both sheets and
      // compare pixel-by-pixel.
      for (final spriteA in sheetA.sprites) {
        final name = spriteA.sprite.name;

        // Find the same icon in sheet B.
        final spriteB = sheetB.sprites.firstWhere((s) => s.sprite.name == name);

        final regionA = extractIconRegion(
          imageA,
          spriteA.index,
          sheetA.cols,
          spriteSize,
        );
        final regionB = extractIconRegion(
          imageB,
          spriteB.index,
          sheetB.cols,
          spriteSize,
        );

        final diffCount = countDifferingPixels(regionA, regionB);
        expect(
          diffCount,
          equals(0),
          reason:
              'Icon "$name" differs by $diffCount pixels between sheet A '
              '(${sheetA.sprites.length} icons, cols=${sheetA.cols}, '
              'index=${spriteA.index}) and sheet B '
              '(${sheetB.sprites.length} icons, cols=${sheetB.cols}, '
              'index=${spriteB.index})',
        );
      }
    },
    timeout: Timeout(Duration(seconds: 60)),
  );

  test(
    'icon pixel content is stable when adding an icon that changes column count',
    () async {
      const spriteSize = 48;

      // Pick exactly 4 SVGs → cols = ceil(sqrt(4)) = 2
      // Then pick 5 SVGs → cols = ceil(sqrt(5)) = 3
      // This guarantees a column count change.
      final fourFiles = allFiles.sublist(0, 4);
      final fiveFiles = allFiles.sublist(0, 5);

      expect(sqrt(4).ceil(), 2);
      expect(sqrt(5).ceil(), 3);

      final sheetSmall = await Spritesheet.fromFiles(
        files: fourFiles,
        spriteSize: spriteSize,
      );
      final sheetLarge = await Spritesheet.fromFiles(
        files: fiveFiles,
        spriteSize: spriteSize,
      );

      expect(sheetSmall.cols, equals(2));
      expect(sheetLarge.cols, equals(3));

      final bytesSmall = await SpritesheetRenderer().render(sheetSmall);
      final bytesLarge = await SpritesheetRenderer().render(sheetLarge);
      final imageSmall = decodePng(bytesSmall)!;
      final imageLarge = decodePng(bytesLarge)!;

      // Every icon from the 4-icon sheet must be pixel-identical in the
      // 5-icon sheet.
      for (final sprite in sheetSmall.sprites) {
        final name = sprite.sprite.name;
        final other = sheetLarge.sprites.firstWhere(
          (s) => s.sprite.name == name,
        );

        final regionSmall = extractIconRegion(
          imageSmall,
          sprite.index,
          sheetSmall.cols,
          spriteSize,
        );
        final regionLarge = extractIconRegion(
          imageLarge,
          other.index,
          sheetLarge.cols,
          spriteSize,
        );

        final diffCount = countDifferingPixels(regionSmall, regionLarge);
        expect(
          diffCount,
          equals(0),
          reason:
              'Icon "$name" differs by $diffCount pixels between 4-icon sheet '
              '(cols=${sheetSmall.cols}, index=${sprite.index}) and 5-icon sheet '
              '(cols=${sheetLarge.cols}, index=${other.index})',
        );
      }
    },
    timeout: Timeout(Duration(seconds: 60)),
  );
}
