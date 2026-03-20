import 'dart:io';

import 'package:icon_bundler/src/utils.dart';
import 'package:test/test.dart';

/// True when fitted widths scale linearly with square cell side [s]:
/// `width(si) * sj == width(sj) * si` for all pairs from [squareCellSides].
///
/// This is the condition you want when the same logical icon is rasterized at
/// 1× / 2× / 3× cell sizes (e.g. 24 / 48 / 72 from base 24 with @2x and @3x).
/// Truncating division in [fitSize] breaks it for slightly non-square sources
/// (see dominos.svg viewBox), which shifts content by a pixel between variants
/// and breaks goldens.
bool fittedWidthsAreProportional(
  double sourceWidth,
  double sourceHeight,
  List<int> squareCellSides,
  ({int width, int height}) Function(
    double sw,
    double sh,
    int outW,
    int outH,
  ) fit,
) {
  final widths = <int>[
    for (final s in squareCellSides) fit(sourceWidth, sourceHeight, s, s).width,
  ];
  for (var i = 0; i < squareCellSides.length; i++) {
    for (var j = i + 1; j < squareCellSides.length; j++) {
      final si = squareCellSides[i];
      final sj = squareCellSides[j];
      if (widths[i] * sj != widths[j] * si) return false;
    }
  }
  return true;
}

/// Mirrors the historical bug: `.toInt()` on scaled dimensions (truncate
/// toward zero for positive values).
({int width, int height}) fitSizeTruncating(
  double sourceWidth,
  double sourceHeight,
  int outputWidth,
  int outputHeight,
) {
  if (outputWidth / outputHeight > sourceWidth / sourceHeight) {
    return (
      width: (sourceWidth * outputHeight / sourceHeight).toInt(),
      height: outputHeight,
    );
  }
  return (
    width: outputWidth,
    height: (sourceHeight * outputWidth / sourceWidth).toInt(),
  );
}

void main() {
  group('multiscale fitSize (2x/3x sprite variants)', () {
    // dominos.svg viewBox width/height (slightly non-square → truncation drift).
    const dominosViewBoxW = 162.9;
    const dominosViewBoxH = 163.7;
    const variantSides = [24, 48, 72];

    test('truncating fit breaks proportional width across 24/48/72 cells', () {
      expect(
        fittedWidthsAreProportional(
          dominosViewBoxW,
          dominosViewBoxH,
          variantSides,
          fitSizeTruncating,
        ),
        isFalse,
        reason:
            'Sanity check: truncation should fail this invariant for dominos.svg.',
      );
    });

    test(
      'fitSize keeps fitted width proportional for 24/48/72 (2x/3x of base 24)',
      () {
        expect(
          fittedWidthsAreProportional(
            dominosViewBoxW,
            dominosViewBoxH,
            variantSides,
            fitSize,
          ),
          isTrue,
          reason:
              'Without this, the same icon shifts by ~1px between @2x and @3x '
              'sheet variants and grid-regeneration goldens become flaky.',
        );
      },
    );

    test('parsed dominos.svg viewBox satisfies the same invariant', () async {
      final svgFile = File('example/input/dominos.svg');
      expect(svgFile.existsSync(), isTrue, reason: 'example asset missing');
      final size = parseSvgSize(await svgFile.readAsString());
      expect(
        fittedWidthsAreProportional(
          size.width,
          size.height,
          variantSides,
          fitSize,
        ),
        isTrue,
      );
    });
  });
}
