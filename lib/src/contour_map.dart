import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// An image that holds, for each of its pixels, how far along a band the
/// point at its centre is, so that a shader can color a border along its
/// length without the band's triangles.
///
/// Each pixel holds the band's texture x coordinate there, as a fraction of
/// the band's length, in 24 bits: its red, green and blue bytes, most
/// significant first. Pixels the band does not cover take the value of a
/// covered pixel next to them, which fills the small gaps between the band's
/// pieces, and are otherwise 0.
///
/// The image is uploaded asynchronously; [image] is null until it is ready.
class ContourMap {
  ContourMap._(this.origin, this.scale, this.width, this.height);

  /// Builds the map of the band whose triangles have [positions] and
  /// [coordinates], as described in `ContourBand`, at [scale] pixels per
  /// logical pixel, covering [bounds]. Returns null if the map would be too
  /// large.
  static ContourMap? build({
    required Float32List positions,
    required Float32List coordinates,
    required Rect bounds,
    required double length,
    required double scale,
  }) {
    // A pixel's border on each side, so that every pixel the band reaches
    // into is in the map.
    final Offset origin = bounds.topLeft - Offset(1 / scale, 1 / scale);
    final int width = (bounds.width * scale).ceil() + 2;
    final int height = (bounds.height * scale).ceil() + 2;
    if (width * height > _maxPixels) {
      return null;
    }
    final ContourMap map = ContourMap._(origin, scale, width, height);
    map._upload(
      _encode(
        _rasterize(positions, coordinates, origin, scale, width, height),
        length,
        width,
        height,
      ),
    );
    return map;
  }

  /// The most pixels a map may have: 16 MB of memory.
  static const int _maxPixels = 4 * 1024 * 1024;

  /// Where the top-left corner of the map's first pixel is, in the band's
  /// coordinates.
  final Offset origin;

  /// The map's pixels per logical pixel.
  final double scale;

  /// The width of the map, in pixels.
  final int width;

  /// The height of the map, in pixels.
  final int height;

  /// The map, or null while it is being uploaded.
  ui.Image? get image => _image;
  ui.Image? _image;

  bool _disposed = false;

  void _upload(Uint8List pixels) {
    final Completer<void> uploaded = Completer<void>();
    _pendingUploads.add(uploaded.future);
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      ui.Image image,
    ) {
      if (_disposed) {
        image.dispose();
      } else {
        _image = image;
      }
      _pendingUploads.remove(uploaded.future);
      uploaded.complete();
    });
  }

  /// Releases the image, now or once it is uploaded.
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
  }

  /// The band's texture x coordinate at the centre of each pixel, or NaN
  /// where the band does not reach.
  static Float32List _rasterize(
    Float32List positions,
    Float32List coordinates,
    Offset origin,
    double scale,
    int width,
    int height,
  ) {
    final Float32List along = Float32List(width * height)
      ..fillRange(0, width * height, double.nan);
    // Triangles are drawn in order, and each covers the ones before it, as
    // when the band is drawn with BlendMode.src.
    for (int t = 0; t + 5 < positions.length; t += 6) {
      final double ax = (positions[t] - origin.dx) * scale;
      final double ay = (positions[t + 1] - origin.dy) * scale;
      final double bx = (positions[t + 2] - origin.dx) * scale;
      final double by = (positions[t + 3] - origin.dy) * scale;
      final double cx = (positions[t + 4] - origin.dx) * scale;
      final double cy = (positions[t + 5] - origin.dy) * scale;
      final double area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      if (area.abs() < 1e-12) {
        continue;
      }
      final double ua = coordinates[t];
      final double ub = coordinates[t + 2];
      final double uc = coordinates[t + 4];
      // The centres of the pixels inside the triangle's bounds.
      final int left = math.max(
        0,
        (math.min(ax, math.min(bx, cx)) - 0.5).ceil(),
      );
      final int right = math.min(
        width - 1,
        (math.max(ax, math.max(bx, cx)) - 0.5).floor(),
      );
      final int top = math.max(
        0,
        (math.min(ay, math.min(by, cy)) - 0.5).ceil(),
      );
      final int bottom = math.min(
        height - 1,
        (math.max(ay, math.max(by, cy)) - 0.5).floor(),
      );
      for (int y = top; y <= bottom; y++) {
        final double py = y + 0.5;
        for (int x = left; x <= right; x++) {
          final double px = x + 0.5;
          // How far the centre is towards each corner, as a fraction.
          final double wa =
              ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area;
          final double wb =
              ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area;
          final double wc = 1 - wa - wb;
          if (wa < -1e-6 || wb < -1e-6 || wc < -1e-6) {
            continue;
          }
          along[y * width + x] = wa * ua + wb * ub + wc * uc;
        }
      }
    }
    _fillGaps(along, width, height);
    return along;
  }

  /// Gives pixels the band does not reach the value of a neighbour it does,
  /// up to [_gapWidth] pixels away.
  static void _fillGaps(Float32List along, int width, int height) {
    for (int pass = 0; pass < _gapWidth; pass++) {
      final Float32List before = Float32List.fromList(along);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int i = y * width + x;
          if (!before[i].isNaN) {
            continue;
          }
          if (x > 0 && !before[i - 1].isNaN) {
            along[i] = before[i - 1];
          } else if (x < width - 1 && !before[i + 1].isNaN) {
            along[i] = before[i + 1];
          } else if (y > 0 && !before[i - width].isNaN) {
            along[i] = before[i - width];
          } else if (y < height - 1 && !before[i + width].isNaN) {
            along[i] = before[i + width];
          }
        }
      }
    }
  }

  /// How many pixels wide a gap between the band's pieces can be filled.
  static const int _gapWidth = 2;

  static Uint8List _encode(
    Float32List along,
    double length,
    int width,
    int height,
  ) {
    final Uint8List pixels = Uint8List(width * height * 4);
    for (int i = 0; i < along.length; i++) {
      final double u = along[i];
      if (u.isNaN) {
        continue;
      }
      // The band can run along more than one period of the gradient.
      final double fraction = u / length - (u / length).floorToDouble();
      final int value = (fraction * 16777216).floor().clamp(0, 16777215);
      pixels[i * 4] = value >> 16;
      pixels[i * 4 + 1] = (value >> 8) & 0xFF;
      pixels[i * 4 + 2] = value & 0xFF;
      pixels[i * 4 + 3] = 0xFF;
    }
    return pixels;
  }
}

final Set<Future<void>> _pendingUploads = <Future<void>>{};

/// Completes once every map that is being uploaded is ready.
@visibleForTesting
Future<void> contourMapsUploaded() async {
  while (_pendingUploads.isNotEmpty) {
    await Future.wait(_pendingUploads.toList());
  }
}
