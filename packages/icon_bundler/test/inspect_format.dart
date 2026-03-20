import 'dart:io';
import 'package:image/image.dart';

void main() {
  final bytes = File('example/input/flutter.png').readAsBytesSync();
  final img = decodePng(bytes)!;
  print(
    'flutter.png - format: ${img.format}, channels: ${img.numChannels}, w: ${img.width}, h: ${img.height}',
  );
}
