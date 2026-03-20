import 'dart:io';
import 'dart:math';

import 'package:icon_bundler/src/spritesheet.dart';
import 'package:icon_bundler/src/renderer.dart';
import 'package:image/image.dart';

/// Extracts the pixel region for a given icon from a spritesheet PNG.
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

void main() async {
  final inputDir = Directory('example/input');
  final supportedExts = {'.svg', '.png', '.jpg', '.jpeg'};
  final allFiles =
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

  print('Total files: ${allFiles.length}');
  for (var f in allFiles) {
    print('  ${f.path}');
  }

  // Generate with 4 icons (cols=2) and 9 icons (cols=3)
  const spriteSize = 24;
  final subset = allFiles.sublist(0, 4);
  final all = allFiles;

  final sheetSmall = await Spritesheet.fromFiles(
    files: subset,
    spriteSize: spriteSize,
  );
  final sheetLarge = await Spritesheet.fromFiles(
    files: all,
    spriteSize: spriteSize,
  );

  print(
    '\nSmall sheet: ${sheetSmall.sprites.length} icons, cols=${sheetSmall.cols}, ${sheetSmall.width}x${sheetSmall.height}',
  );
  print(
    'Large sheet: ${sheetLarge.sprites.length} icons, cols=${sheetLarge.cols}, ${sheetLarge.width}x${sheetLarge.height}',
  );

  final bytesSmall = await SpritesheetRenderer().render(sheetSmall);
  final bytesLarge = await SpritesheetRenderer().render(sheetLarge);
  final imageSmall = decodePng(bytesSmall)!;
  final imageLarge = decodePng(bytesLarge)!;

  print(
    '\nSmall sheet image: ${imageSmall.width}x${imageSmall.height}, format=${imageSmall.format}, channels=${imageSmall.numChannels}',
  );
  print(
    'Large sheet image: ${imageLarge.width}x${imageLarge.height}, format=${imageLarge.format}, channels=${imageLarge.numChannels}',
  );

  // List sprites in each sheet
  print('\nSmall sheet sprites:');
  for (var s in sheetSmall.sprites) {
    print(
      '  ${s.sprite.name}: index=${s.index}, left=${s.left}, top=${s.top}, ${s.width}x${s.height}',
    );
  }
  print('\nLarge sheet sprites:');
  for (var s in sheetLarge.sprites) {
    print(
      '  ${s.sprite.name}: index=${s.index}, left=${s.left}, top=${s.top}, ${s.width}x${s.height}',
    );
  }

  // Compare shared icons
  print('\nComparing shared icons:');
  for (var spriteSmall in sheetSmall.sprites) {
    final name = spriteSmall.sprite.name;
    final spriteLarge = sheetLarge.sprites.firstWhere(
      (s) => s.sprite.name == name,
    );

    final regionSmall = extractIconRegion(
      imageSmall,
      spriteSmall.index,
      sheetSmall.cols,
      spriteSize,
    );
    final regionLarge = extractIconRegion(
      imageLarge,
      spriteLarge.index,
      sheetLarge.cols,
      spriteSize,
    );

    var diffCount = 0;
    var maxDiff = 0;
    for (var y = 0; y < regionSmall.height; y++) {
      for (var x = 0; x < regionSmall.width; x++) {
        final a = regionSmall.getPixel(x, y);
        final b = regionLarge.getPixel(x, y);
        if (a != b) {
          diffCount++;
          final dr = (a.r.toInt() - b.r.toInt()).abs();
          final dg = (a.g.toInt() - b.g.toInt()).abs();
          final db = (a.b.toInt() - b.b.toInt()).abs();
          final da = (a.a.toInt() - b.a.toInt()).abs();
          final d = [dr, dg, db, da].reduce(max);
          if (d > maxDiff) maxDiff = d;
          if (diffCount <= 5) {
            print('    Diff at ($x,$y): small=$a large=$b');
          }
        }
      }
    }
    print(
      '  $name: ${diffCount == 0 ? "IDENTICAL" : "DIFFERS by $diffCount pixels (max channel diff: $maxDiff)"}',
    );
  }

  // Also dump the small sheet to disk for visual inspection
  File('test/debug_sheet_small.png').writeAsBytesSync(bytesSmall);
  File('test/debug_sheet_large.png').writeAsBytesSync(bytesLarge);
  print(
    '\nSaved debug sheets to test/debug_sheet_small.png and test/debug_sheet_large.png',
  );
}
