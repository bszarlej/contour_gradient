// Times each stage of painting a ContourGradientBorder, per shape.
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
import 'package:contour_gradient/src/color_stops.dart';
import 'package:contour_gradient/src/contour_strip.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scale of the canvas. In a frame the canvas is usually not scaled,
/// because the device pixel ratio is applied by the root layer, so the border
/// sees a scale of 1 whatever the device.
const double _scale = 1.0;
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
    step: 2.0 / _scale,
  );
}

void main() {
  test('paint stages', () {
    final List<double> stops = resolveStops(_colors.length, null);
    final StringBuffer out = StringBuffer()
      ..writeln()
      ..writeln(
        'Paint stages at scale $_scale, width $_width, '
        '${_colors.length} colors (debug mode, µs per call)',
      )
      ..writeln(
        '${'shape'.padRight(18)}${'pairs'.padLeft(7)}'
        '${'geometry'.padLeft(10)}${'vertices'.padLeft(10)}'
        '${'paint()'.padLeft(10)}',
      );

    for (final _Case c in _cases) {
      final List<ContourStrip> strips = _strips(c);
      final int pairs = strips.fold(
        0,
        (int sum, ContourStrip s) => sum + s.outer.length,
      );

      final double geometry = _measure((_) => _strips(c));

      final double vertices = _measure((int i) {
        ContourStrip.buildVertices(
          strips,
          colors: _colors,
          stops: stops,
          startOffset: i / 97,
        )?.vertices.dispose();
      });

      final ContourGradientBorder border = c.shape
          .copyWith(side: const BorderSide(width: _width))
          .withGradient(_colors);
      final Rect rect = Offset.zero & c.size;
      ui.PictureRecorder recorder = ui.PictureRecorder();
      Canvas canvas = Canvas(recorder)..scale(_scale);
      final double paint = _measure((int i) {
        // Start a new recording now and then, so it does not grow forever.
        if (i % 64 == 0) {
          recorder.endRecording().dispose();
          recorder = ui.PictureRecorder();
          canvas = Canvas(recorder)..scale(_scale);
        }
        border.copyWith(startOffset: i / 97).paint(canvas, rect);
      });
      recorder.endRecording().dispose();

      out.writeln(
        '${c.name.padRight(18)}${'$pairs'.padLeft(7)}'
        '${geometry.toStringAsFixed(0).padLeft(10)}'
        '${vertices.toStringAsFixed(0).padLeft(10)}'
        '${paint.toStringAsFixed(0).padLeft(10)}',
      );
    }
    print(out);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
