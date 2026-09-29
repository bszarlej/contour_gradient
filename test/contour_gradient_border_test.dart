import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:contour_gradient/contour_gradient.dart';
import 'package:contour_gradient/src/color_stops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color red = Color(0xFFFF0000);
const Color blue = Color(0xFF0000FF);

/// Paints [border] around a box of [size] and returns the pixels, with a
/// margin of [pad] around the box.
///
/// If [atOrigin] is true, the canvas is moved so that the box starts at the
/// origin, which [LinearBorder] needs to paint in the right place.
Future<Pixels> render(
  ShapeBorder border,
  Size size, {
  double pad = 20,
  bool atOrigin = false,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  if (atOrigin) {
    canvas.translate(pad, pad);
  }
  border.paint(
    canvas,
    (atOrigin ? Offset.zero : Offset(pad, pad)) & size,
    textDirection: TextDirection.ltr,
  );
  final ui.Picture picture = recorder.endRecording();
  final int width = (size.width + 2 * pad).ceil();
  final int height = (size.height + 2 * pad).ceil();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData data = (await image.toByteData())!;
  image.dispose();
  picture.dispose();
  return Pixels(data, width, height, pad);
}

class Pixels {
  Pixels(this.data, this.width, this.height, this.pad);

  final ByteData data;
  final int width;
  final int height;
  final double pad;

  /// The color of the pixel at [x], [y] relative to the box's top left.
  Color at(double x, double y) {
    final int i = (((y + pad).floor()) * width + (x + pad).floor()) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  int alphaAt(int index) => data.getUint8(index * 4 + 3);
}

Matcher isColorCloseTo(Color expected, {double tolerance = 0.03}) {
  return predicate<Color>(
    (Color c) =>
        (c.r - expected.r).abs() <= tolerance &&
        (c.g - expected.g).abs() <= tolerance &&
        (c.b - expected.b).abs() <= tolerance &&
        (c.a - expected.a).abs() <= tolerance,
    'is within $tolerance of $expected',
  );
}

void main() {
  group('coverage matches the shape painted by Flutter', () {
    // Each shape is painted as a solid border by Flutter, and as a gradient
    // border whose colors are all the same. The two must cover the same
    // pixels.
    const Size wide = Size(140, 90);
    final Map<String, (OutlinedBorder, Size)> shapes =
        <String, (OutlinedBorder, Size)>{
          'rectangle': (const RoundedRectangleBorder(), wide),
          'rounded rectangle': (
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            wide,
          ),
          'radius smaller than width': (
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(3)),
            ),
            wide,
          ),
          'elliptical, mixed corners': (
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.elliptical(40, 15),
                topRight: Radius.circular(3),
                bottomRight: Radius.elliptical(10, 35),
              ),
            ),
            wide,
          ),
          'huge radius': (
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(1000)),
            ),
            wide,
          ),
          'stadium': (const StadiumBorder(), const Size(160, 60)),
          'circle': (const CircleBorder(), wide),
          'oval': (const OvalBorder(), wide),
          'eccentric circle': (const CircleBorder(eccentricity: 0.5), wide),
          'star': (
            const StarBorder(innerRadiusRatio: 0.45),
            const Size(120, 120),
          ),
          'rounded star': (
            const StarBorder(
              points: 7,
              innerRadiusRatio: 0.6,
              pointRounding: 0.5,
              valleyRounding: 0.3,
              rotation: 20,
            ),
            wide,
          ),
          'polygon': (const StarBorder.polygon(sides: 6), wide),
          'beveled': (
            const BeveledRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            wide,
          ),
          'continuous': (
            const ContinuousRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(40)),
            ),
            wide,
          ),
          'superellipse': (
            const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(30)),
            ),
            wide,
          ),
          'linear': (
            const LinearBorder(
              start: LinearBorderEdge(size: 0.5),
              bottom: LinearBorderEdge(alignment: 1),
            ),
            wide,
          ),
        };
    const Map<String, double> aligns = <String, double>{
      'inside': BorderSide.strokeAlignInside,
      'center': BorderSide.strokeAlignCenter,
      'outside': BorderSide.strokeAlignOutside,
    };
    const List<double> widths = <double>[1.5, 9];

    Future<int> maxAlphaDifference(
      OutlinedBorder shape,
      Size size,
      BorderSide side,
      List<Color> colors,
    ) async {
      // Flutter's own LinearBorder only paints correctly at the origin; the
      // gradient border must match it at an offset. Other shapes are painted
      // at the same offset, since some edge pixels differ slightly when the
      // canvas is moved instead.
      final Pixels expected = await render(
        shape.copyWith(side: side),
        size,
        atOrigin: shape is LinearBorder,
      );
      final Pixels actual = await render(
        ContourGradientBorder(colors: colors, shape: shape, side: side),
        size,
      );
      int maxDiff = 0;
      for (int i = 0; i < expected.width * expected.height; i++) {
        final int diff = (expected.alphaAt(i) - actual.alphaAt(i)).abs();
        if (diff > maxDiff) {
          maxDiff = diff;
        }
      }
      return maxDiff;
    }

    for (final MapEntry<String, (OutlinedBorder, Size)> shape
        in shapes.entries) {
      for (final MapEntry<String, double> align in aligns.entries) {
        for (final double width in widths) {
          test('${shape.key}, width $width, stroke ${align.key}', () async {
            final (OutlinedBorder border, Size size) = shape.value;
            final BorderSide side = BorderSide(
              color: red,
              width: width,
              strokeAlign: align.value,
            );
            // Anti-aliased edges may differ slightly between drawing a shape
            // and clipping to it, but no pixel may be missing or extra.
            expect(
              await maxAlphaDifference(border, size, side, const <Color>[
                red,
                red,
              ]),
              lessThanOrEqualTo(40),
            );
          });
        }
      }
    }

    test('width that fills the box', () async {
      expect(
        await maxAlphaDifference(
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          const Size(60, 40),
          const BorderSide(color: red, width: 30),
          const <Color>[red, red],
        ),
        lessThanOrEqualTo(40),
      );
    });

    test(
      'translucent colors do not build up where the band overlaps',
      () async {
        const Color faded = Color(0x80FF0000);
        for (final OutlinedBorder shape in <OutlinedBorder>[
          const StarBorder(innerRadiusRatio: 0.3),
          const BeveledRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ]) {
          expect(
            await maxAlphaDifference(
              shape,
              const Size(120, 120),
              const BorderSide(color: faded, width: 8),
              const <Color>[faded, faded],
            ),
            lessThanOrEqualTo(40),
          );
        }
      },
    );
  });

  group('color placement', () {
    // A 100x100 box with a 10 wide border: the centre line is a 90x90 square.
    // The gradient starts halfway around the top-left corner, so the middle
    // of each side is 1/8, 3/8, 5/8 and 7/8 of the way around.
    const Size size = Size(100, 100);
    const BorderSide side = BorderSide(width: 10);

    Color lerpAt(double t) => Color.lerp(red, blue, t)!;

    // Red and blue with even stops wrap around: red at 0.0, blue at 0.5 and
    // red again at 1.0.
    Color wrappedAt(double t) => lerpAt(t <= 0.5 ? 2 * t : 2 - 2 * t);

    test('runs clockwise from the top-left corner', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(colors: <Color>[red, blue], side: side),
        size,
      );
      expect(pixels.at(50, 5), isColorCloseTo(wrappedAt(0.125)));
      expect(pixels.at(95, 50), isColorCloseTo(wrappedAt(0.375)));
      expect(pixels.at(50, 95), isColorCloseTo(wrappedAt(0.625)));
      expect(pixels.at(5, 50), isColorCloseTo(wrappedAt(0.875)));
    });

    test('spaces colors evenly and wraps back to the first', () async {
      // The centre line is 360 long; each of three colors gets 120 of it.
      const Color green = Color(0xFF00FF00);
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue, green],
          side: side,
        ),
        size,
      );
      expect(pixels.at(65, 5), isColorCloseTo(Color.lerp(red, blue, 0.5)!));
      expect(pixels.at(95, 35), isColorCloseTo(blue));
      expect(pixels.at(35, 95), isColorCloseTo(green));
      expect(pixels.at(5, 65), isColorCloseTo(Color.lerp(green, red, 0.5)!));
    });

    test('wrapColorStops blends from the last stop to the first', () {
      final ({List<Color> colors, List<double> stops}) wrapped = wrapColorStops(
        const <Color>[red, blue],
        const <double>[0.2, 0.6],
      );
      expect(wrapped.stops, <double>[0.0, 0.2, 0.6, 1.0]);
      // 0.0 is two thirds of the way through the gap from 0.6 round to 1.2.
      expect(
        wrapped.colors.first,
        isColorCloseTo(Color.lerp(blue, red, 0.4 / 0.6)!, tolerance: 1e-6),
      );
      expect(wrapped.colors.last, wrapped.colors.first);

      final ({List<Color> colors, List<double> stops}) full = wrapColorStops(
        const <Color>[red, blue],
        const <double>[0.0, 1.0],
      );
      expect(full.stops, <double>[0.0, 1.0]);
    });

    test('is uniform across the width of the border', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(colors: <Color>[red, blue], side: side),
        size,
      );
      expect(pixels.at(50, 1), isColorCloseTo(pixels.at(50, 8)));
      expect(pixels.at(99, 30), isColorCloseTo(pixels.at(91, 30)));
    });

    test('startOffset moves the gradient clockwise', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue],
          startOffset: 0.25,
          side: side,
        ),
        size,
      );
      expect(pixels.at(50, 5), isColorCloseTo(wrappedAt(0.375)));
      expect(pixels.at(5, 50), isColorCloseTo(wrappedAt(0.125)));
    });

    test('follows the length of a wide box, unlike a sweep', () async {
      // On a 400x40 box, the midpoint of the gradient is halfway along the
      // perimeter, which is the far end of the bottom edge from the start.
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue],
          stops: <double>[0.25, 0.75],
          side: side,
        ),
        const Size(400, 40),
      );
      // Centre line: 390x30, perimeter 840. The middle of the top edge is at
      // 15 + 180 = 195, t = 0.232, before the first stop, where the gradient
      // blends from blue at 0.75 round to red at 1.25.
      expect(
        pixels.at(200, 5),
        isColorCloseTo(Color.lerp(blue, red, (195 / 840 + 0.25) * 2)!),
      );
      // The middle of the bottom edge is at 195 + 30 + 390... = 615 of 840.
      expect(
        pixels.at(200, 35),
        isColorCloseTo(lerpAt((615 / 840 - 0.25) * 2)),
      );
    });

    test('hard stops stay sharp', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, red, blue, blue],
          stops: <double>[0.0, 0.5, 0.5, 1.0],
          side: side,
        ),
        size,
      );
      expect(pixels.at(50, 5), red);
      expect(pixels.at(95, 50), red);
      // The stop is at the bottom-right corner, on its diagonal.
      expect(pixels.at(97, 90), red);
      expect(pixels.at(90, 97), blue);
      expect(pixels.at(50, 95), blue);
      expect(pixels.at(5, 50), blue);
    });

    test('masked shapes place colors like the direct path', () async {
      // A beveled rectangle without bevels is a rectangle, but goes through
      // the generic, masked path.
      const List<Color> colors = <Color>[red, blue, Color(0xFF00FF00), red];
      final Pixels direct = await render(
        const ContourGradientBorder(colors: colors, side: side),
        size,
      );
      final Pixels masked = await render(
        const ContourGradientBorder(
          colors: colors,
          shape: BeveledRectangleBorder(),
          side: side,
        ),
        size,
      );
      for (final (double x, double y) in <(double, double)>[
        (30, 5),
        (50, 5),
        (80, 3),
        (95, 20),
        (97, 60),
        (60, 95),
        (20, 92),
        (5, 70),
        (5, 25),
      ]) {
        expect(
          masked.at(x, y),
          isColorCloseTo(direct.at(x, y)),
          reason: '($x, $y)',
        );
      }
    });

    test('an underline runs the whole gradient left to right', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue],
          shape: LinearBorder(bottom: LinearBorderEdge()),
          side: side,
        ),
        size,
      );
      // The line runs along y = 95 from x = -1 to 101, extended by a pixel
      // at each end, and does not wrap.
      for (final double x in <double>[2, 25, 50, 75, 97]) {
        expect(
          pixels.at(x, 95),
          isColorCloseTo(lerpAt((x + 1.5) / 102)),
          reason: 'x = $x',
        );
      }
    });

    test('LinearBorder edges that meet form one line', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue],
          shape: LinearBorder(
            start: LinearBorderEdge(),
            bottom: LinearBorderEdge(),
          ),
          side: side,
        ),
        size,
      );
      // Down the start edge from its top, round the corner at (5, 95), then
      // along the bottom: 96 + 96 long, so the corner is halfway.
      expect(pixels.at(5, 1), isColorCloseTo(red, tolerance: 0.05));
      expect(pixels.at(5, 50), isColorCloseTo(lerpAt(52 / 192)));
      expect(pixels.at(50, 95), isColorCloseTo(lerpAt((96 + 46) / 192)));
      expect(pixels.at(98, 95), isColorCloseTo(blue, tolerance: 0.05));
    });

    test('a single color paints a solid border', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(colors: <Color>[red], side: side),
        size,
      );
      expect(pixels.at(50, 5), red);
      expect(pixels.at(50, 50), const Color(0x00000000));
    });

    test('BorderStyle.none and zero width paint nothing', () async {
      for (final BorderSide side in const <BorderSide>[
        BorderSide(width: 4, style: BorderStyle.none),
        BorderSide(width: 0),
      ]) {
        final Pixels pixels = await render(
          ContourGradientBorder(colors: const <Color>[red, blue], side: side),
          size,
        );
        expect(pixels.at(50, 0), const Color(0x00000000));
      }
    });

    test('invalid stops throw in debug mode', () {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      expect(
        () => const ContourGradientBorder(
          colors: <Color>[red, blue],
          stops: <double>[0.0],
        ).paint(Canvas(recorder), Offset.zero & size),
        throwsArgumentError,
      );
      expect(
        () => const ContourGradientBorder(
          colors: <Color>[red, blue],
          stops: <double>[0.8, 0.2],
        ).paint(Canvas(recorder), Offset.zero & size),
        throwsArgumentError,
      );
      recorder.endRecording().dispose();
    });
  });

  group('ShapeBorder contract', () {
    const ContourGradientBorder border = ContourGradientBorder(
      colors: <Color>[red, blue],
      stops: <double>[0.2, 0.8],
      startOffset: 0.1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      side: BorderSide(width: 4),
    );

    test('equality and hashCode', () {
      final ContourGradientBorder same = ContourGradientBorder(
        colors: <Color>[red, blue],
        stops: <double>[0.2, 0.8],
        startOffset: 0.1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(width: 4),
      );
      expect(same, border);
      expect(same.hashCode, border.hashCode);
      expect(border.copyWith(colors: <Color>[blue, red]), isNot(border));
      expect(border.copyWith(startOffset: 0.2), isNot(border));
      expect(border.copyWith(shape: const StadiumBorder()), isNot(border));
    });

    test('copyWith', () {
      final ContourGradientBorder copy = border.copyWith(
        side: const BorderSide(width: 2),
      );
      expect(copy.side.width, 2);
      expect(copy.colors, border.colors);
      expect(copy.stops, border.stops);
      expect(copy.shape, border.shape);
      expect(copy.startOffset, border.startOffset);
    });

    test('dimensions depend on strokeAlign', () {
      expect(border.dimensions, const EdgeInsets.all(4));
      expect(
        border
            .copyWith(
              side: const BorderSide(
                width: 4,
                strokeAlign: BorderSide.strokeAlignCenter,
              ),
            )
            .dimensions,
        const EdgeInsets.all(2),
      );
      expect(
        border
            .copyWith(
              side: const BorderSide(
                width: 4,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            )
            .dimensions,
        EdgeInsets.zero,
      );
    });

    test('scale', () {
      final ContourGradientBorder scaled = border.scale(2);
      expect(scaled.side.width, 8);
      expect(
        scaled.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
      expect(scaled.colors, border.colors);
    });

    test('lerp between gradient borders', () {
      const ContourGradientBorder other = ContourGradientBorder(
        colors: <Color>[blue, blue, red],
        startOffset: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        side: BorderSide(width: 8),
      );
      final ContourGradientBorder mid =
          ShapeBorder.lerp(border, other, 0.5)! as ContourGradientBorder;
      expect(mid.side.width, 6);
      expect(mid.startOffset, closeTo(0.3, 1e-9));
      expect(
        mid.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
      // Sampled at the union of both gradients' stops, once wrapped around:
      // 0.2 and 0.8 from one, thirds from the other's three even colors.
      final List<double> midStops = mid.stops!;
      expect(midStops.length, 6);
      for (final (int i, double stop) in <(int, double)>[
        (0, 0.0),
        (1, 0.2),
        (2, 1 / 3),
        (3, 2 / 3),
        (4, 0.8),
        (5, 1.0),
      ]) {
        expect(midStops[i], closeTo(stop, 1e-9));
      }

      final ContourGradientBorder start =
          ShapeBorder.lerp(border, other, 0.0)! as ContourGradientBorder;
      final ({List<Color> colors, List<double> stops}) wrapped = wrapColorStops(
        border.colors,
        border.stops,
      );
      final List<double> stops = start.stops!;
      for (int i = 0; i < stops.length; i++) {
        expect(
          start.colors[i],
          isColorCloseTo(
            colorAt(wrapped.colors, wrapped.stops, stops[i]),
            tolerance: 1e-6,
          ),
        );
      }
    });

    test('lerp keeps evenly spaced colors wrapping around', () {
      // Buttons and chips animate every change to their shape, so they paint
      // lerped borders; these must still end in the color they start with.
      const ContourGradientBorder even = ContourGradientBorder(
        colors: <Color>[red, blue, Color(0xFF00FF00)],
      );
      final ContourGradientBorder mid =
          ShapeBorder.lerp(even, even.copyWith(startOffset: 0.5), 0.5)!
              as ContourGradientBorder;
      expect(mid.colors.last, mid.colors.first);
      expect(mid.stops!.first, 0.0);
      expect(mid.stops!.last, 1.0);
      // Each color keeps an equal share.
      expect(mid.stops![1], closeTo(1 / 3, 1e-9));
      expect(mid.stops![2], closeTo(2 / 3, 1e-9));
    });

    test('lerp moves startOffset the short way round', () {
      // A repeating animation wraps from 0.9 to 0.1; halfway between them is
      // 1.0, not 0.5.
      final ContourGradientBorder mid =
          ShapeBorder.lerp(
                border.copyWith(startOffset: 0.9),
                border.copyWith(startOffset: 0.1),
                0.5,
              )!
              as ContourGradientBorder;
      expect(mid.startOffset, closeTo(1.0, 1e-9));
    });

    test('lerp from and to RoundedRectangleBorder', () {
      const RoundedRectangleBorder plain = RoundedRectangleBorder(
        side: BorderSide(color: Color(0xFF00FF00), width: 2),
      );
      final ShapeBorder from = ShapeBorder.lerp(plain, border, 0.5)!;
      final ShapeBorder to = ShapeBorder.lerp(border, plain, 0.5)!;
      expect(from, isA<ContourGradientBorder>());
      expect(to, isA<ContourGradientBorder>());
      expect((from as ContourGradientBorder).side.width, 3);
      expect(from, to);
    });

    test('lerp between different shapes', () {
      const ContourGradientBorder star = ContourGradientBorder(
        colors: <Color>[red, blue],
        shape: StarBorder(),
      );
      final ShapeBorder mid = ShapeBorder.lerp(
        const StadiumBorder(side: BorderSide(color: red)),
        star,
        0.5,
      )!;
      expect(mid, isA<ContourGradientBorder>());
    });

    test('lerp keeps hard stops sharp', () {
      final ({List<Color> colors, List<double> stops}) mid = lerpColorStops(
        const <Color>[red, red, blue, blue],
        const <double>[0.0, 0.5, 0.5, 1.0],
        const <Color>[red, blue],
        null,
        0.5,
      );
      expect(mid.stops, <double>[0.0, 0.5, 0.5, 1.0]);
      expect(mid.colors[1], isNot(mid.colors[2]));
    });
  });

  group('ContourGradientInputBorder', () {
    const Size size = Size(200, 56);

    /// Paints [border] like an InputDecorator does, with a label gap if
    /// [gapExtent] is non-zero.
    Future<Pixels> renderInput(
      InputBorder border, {
      double gapExtent = 0.0,
      double gapPercentage = 1.0,
    }) async {
      const double pad = 20;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder)..translate(pad, pad);
      border.paint(
        canvas,
        Offset.zero & size,
        gapStart: 12,
        gapExtent: gapExtent,
        gapPercentage: gapPercentage,
        textDirection: TextDirection.ltr,
      );
      final ui.Picture picture = recorder.endRecording();
      final int width = (size.width + 2 * pad).ceil();
      final int height = (size.height + 2 * pad).ceil();
      final ui.Image image = await picture.toImage(width, height);
      final ByteData data = (await image.toByteData())!;
      image.dispose();
      picture.dispose();
      return Pixels(data, width, height, pad);
    }

    int maxAlphaDifference(Pixels a, Pixels b) {
      int maxDiff = 0;
      for (int i = 0; i < a.width * a.height; i++) {
        final int diff = (a.alphaAt(i) - b.alphaAt(i)).abs();
        if (diff > maxDiff) {
          maxDiff = diff;
        }
      }
      return maxDiff;
    }

    for (final double radius in <double>[4, 16, 28]) {
      for (final double width in <double>[1, 2, 3]) {
        for (final (double, double) gap in <(double, double)>[
          (40, 0.0),
          (40, 0.5),
          (40, 1.0),
          // Reaches into the top-right corner.
          (170, 1.0),
        ]) {
          final (double gapExtent, double gapPercentage) = gap;
          test('covers the same pixels as OutlineInputBorder: radius $radius, '
              'width $width, gap $gapExtent at $gapPercentage', () async {
            final BorderRadius borderRadius = BorderRadius.circular(radius);
            final BorderSide side = BorderSide(color: red, width: width);
            // The gap starts at 12 - 4 = 8, inside the top-left corner for
            // the larger radii.
            final Pixels expected = await renderInput(
              OutlineInputBorder(borderRadius: borderRadius, borderSide: side),
              gapExtent: gapExtent,
              gapPercentage: gapPercentage,
            );
            final Pixels actual = await renderInput(
              ContourGradientInputBorder(
                colors: const <Color>[red, red],
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                borderSide: side,
              ),
              gapExtent: gapExtent,
              gapPercentage: gapPercentage,
            );
            // Clipping anti-aliases rounded corners and the ends of the
            // gap a little differently from Flutter's stroke, but no pixel
            // may be more than half missing or half extra.
            expect(maxAlphaDifference(expected, actual), lessThan(128));
          });
        }
      }
    }

    test('leaves the label gap empty and paints the gradient', () async {
      final Pixels pixels = await renderInput(
        const ContourGradientInputBorder(
          colors: <Color>[red, blue],
          borderSide: BorderSide(width: 2),
        ),
        gapExtent: 40,
      );
      // The gap runs from x = 8 to 8 + 40 + 8 = 56 along the top.
      expect(pixels.at(30, 0.5).a, 0.0);
      expect(pixels.at(100, 0.5).a, 1.0);
      // Red and blue with even stops: blue is halfway round, at the
      // bottom-right corner, and the top is not blue.
      expect(pixels.at(190, 55), isColorCloseTo(blue, tolerance: 0.15));
      expect(pixels.at(100, 0.5), isNot(isColorCloseTo(blue, tolerance: 0.15)));
    });

    test('lerps from and to OutlineInputBorder', () {
      const ContourGradientInputBorder gradient = ContourGradientInputBorder(
        colors: <Color>[red, blue],
        borderSide: BorderSide(width: 2),
      );
      const OutlineInputBorder outline = OutlineInputBorder(
        borderSide: BorderSide(color: red),
      );
      final ShapeBorder from = ShapeBorder.lerp(outline, gradient, 0.5)!;
      final ShapeBorder to = ShapeBorder.lerp(gradient, outline, 0.5)!;
      expect(from, isA<ContourGradientInputBorder>());
      expect(to, isA<ContourGradientInputBorder>());
      expect((from as ContourGradientInputBorder).borderSide.width, 1.5);
    });

    testWidgets('works in a TextField with a floating label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: ContourGradientInputBorder(
                      colors: <Color>[red, blue],
                      shape: StadiumBorder(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ada');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('in widgets', () {
    testWidgets('works as a button shape', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const ContourGradientBorder(
                  colors: <Color>[red, blue, red],
                  shape: StadiumBorder(),
                ),
                side: const BorderSide(width: 3),
              ),
              onPressed: () {},
              child: const Text('Button'),
            ),
          ),
        ),
      );
      final Material material = tester.widget<Material>(
        find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.byType(Material),
        ),
      );
      final ContourGradientBorder shape =
          material.shape! as ContourGradientBorder;
      // The button applies its own side to the shape.
      expect(shape.side.width, 3);
      expect(shape.colors, <Color>[red, blue, red]);
    });

    testWidgets('animates in AnimatedContainer', (WidgetTester tester) async {
      Widget build(ShapeBorder shape) => MaterialApp(
        home: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 100,
            height: 60,
            decoration: ShapeDecoration(shape: shape),
          ),
        ),
      );
      await tester.pumpWidget(
        build(
          const RoundedRectangleBorder(side: BorderSide(color: red, width: 2)),
        ),
      );
      await tester.pumpWidget(
        build(
          const ContourGradientBorder(
            colors: <Color>[red, blue],
            side: BorderSide(width: 6),
            shape: StarBorder(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final ShapeDecoration decoration =
          tester.widget<Container>(find.byType(Container)).decoration!
              as ShapeDecoration;
      final ContourGradientBorder mid =
          decoration.shape as ContourGradientBorder;
      expect(mid.side.width, greaterThan(2));
      expect(mid.side.width, lessThan(6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
