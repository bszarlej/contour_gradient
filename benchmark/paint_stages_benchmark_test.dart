// Times each stage of painting a ContourGradientBorder, per shape: building
// its strips and its band, which happens on the first paint of a shape and
// size, and painting it again with another start offset, as in an animation.
//
// Run with:
//
//     flutter test benchmark
//
// flutter test runs in debug mode (JIT, asserts on), so use the numbers to
// compare stages and changes against each other, not as absolute costs. For
// AOT numbers on a device, see example/lib/benchmark.dart.

// ignore_for_file: avoid_print, implementation_imports

import 'dart:ui' as ui;

import 'package:contour_gradient/contour_gradient.dart';
import 'package:contour_gradient/src/contour_band.dart';
import 'package:contour_gradient/src/contour_strip.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device pixel ratio, which the border samples its outline for. As in a
/// frame, the canvas itself is not scaled: the root layer applies the ratio.
final double _devicePixelRatio =
    ui.PlatformDispatcher.instance.implicitView!.devicePixelRatio;
const double _width = 3.0;
const List<Color> _colors = <Color>[
  Color(0xFF7F00FF),
  Color(0xFF00C6FF),
  Color(0xFFFF4E50),
  Color(0xFF7F00FF),
];

class _Case {
  const _Case(this.name, this.shape, this.size, {this.rrect});

  final String name;
  final OutlinedBorder shape;
  final Size size;

  /// For shapes painted directly, the outline the border is drawn around.
  final RRect Function(Rect rect)? rrect;
}

final List<_Case> _cases = <_Case>[
  _Case(
    'Rounded rectangle',
    const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    const Size(120, 80),
    rrect: (Rect r) => RRect.fromRectAndRadius(r, const Radius.circular(12)),
  ),
  _Case(
    'Stadium',
    const StadiumBorder(),
    const Size(120, 48),
    rrect: (Rect r) =>
        RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)),
  ),
  const _Case(
    'Beveled',
    BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    Size(120, 80),
  ),
  const _Case(
    'Superellipse',
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
    Size(120, 80),
  ),
  const _Case('Oval', OvalBorder(), Size(120, 80)),
  const _Case('Star', StarBorder(innerRadiusRatio: 0.45), Size(90, 90)),
];

/// Runs [body] repeatedly for about [budget] after a warm-up, and returns
/// the mean time per run in microseconds.
double _measure(
  void Function(int i) body, {
  Duration budget = const Duration(milliseconds: 400),
}) {
  for (int i = 0; i < 20; i++) {
    body(i);
  }
  final Stopwatch watch = Stopwatch()..start();
  int runs = 0;
  while (watch.elapsed < budget) {
    body(runs++);
  }
  return watch.elapsedMicroseconds / runs;
}

/// Builds the strips the way ContourGradientBorder does for [c].
List<ContourStrip> _strips(_Case c) {
  const BorderSide side = BorderSide(width: _width);
  const double margin = 1.0;
  final Rect rect = Offset.zero & c.size;
  final RRect Function(Rect)? rrect = c.rrect;
  if (rrect != null) {
    final RRect outline = rrect(rect);
    return <ContourStrip>[
      ContourStrip.rrectRing(
        outline.inflate(side.strokeOutset + margin).scaleRadii(),
        outline.deflate(side.strokeInset + margin).scaleRadii(),
      ),
    ];
  }
  return ContourStrip.alongPath(
    c.shape.getOuterPath(rect.inflate(side.strokeOffset / 2)),
    halfWidth: side.width + margin,
    step: 2.0 / _devicePixelRatio,
  );
}

void main() {
  test('paint stages', () {
    final StringBuffer out = StringBuffer()
      ..writeln()
      ..writeln(
        'Paint stages at device pixel ratio $_devicePixelRatio, width $_width, '
        '${_colors.length} colors (debug mode, µs per call)',
      )
      ..writeln(
        '${'shape'.padRight(18)}${'pairs'.padLeft(7)}'
        '${'strips'.padLeft(10)}${'band'.padLeft(10)}'
        '${'1st paint'.padLeft(11)}${'paint()'.padLeft(10)}',
      );

    for (final _Case c in _cases) {
      final List<ContourStrip> strips = _strips(c);
      final int pairs = strips.fold(
        0,
        (int sum, ContourStrip s) => sum + s.outer.length,
      );

      final double stripsTime = _measure((_) => _strips(c));

      final double bandTime = _measure((_) {
        ContourBand.fromStrips(strips)?.dispose();
      });

      final ContourGradientBorder border = c.shape
          .copyWith(side: const BorderSide(width: _width))
          .withGradient(_colors);
      final Rect rect = Offset.zero & c.size;
      ui.PictureRecorder recorder = ui.PictureRecorder();
      Canvas canvas = Canvas(recorder);
      double measurePaint({required bool cached}) => _measure((int i) {
        // Start a new recording now and then, so it does not grow forever.
        if (i % 64 == 0) {
          recorder.endRecording().dispose();
          recorder = ui.PictureRecorder();
          canvas = Canvas(recorder);
        }
        if (!cached) {
          contourBandCache.clear();
        }
        border.copyWith(startOffset: i / 97).paint(canvas, rect);
      });
      // The first paint of a shape and size builds its band; later ones, as
      // in an animation, reuse it.
      final double firstPaint = measurePaint(cached: false);
      final double paint = measurePaint(cached: true);
      recorder.endRecording().dispose();

      out.writeln(
        '${c.name.padRight(18)}${'$pairs'.padLeft(7)}'
        '${stripsTime.toStringAsFixed(0).padLeft(10)}'
        '${bandTime.toStringAsFixed(0).padLeft(10)}'
        '${firstPaint.toStringAsFixed(0).padLeft(11)}'
        '${paint.toStringAsFixed(0).padLeft(10)}',
      );
    }
    print(out);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
