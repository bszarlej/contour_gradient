import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:contour_gradient/contour_gradient.dart';
import 'package:contour_gradient/src/color_stops.dart';
import 'package:contour_gradient/src/contour_band.dart';
import 'package:contour_gradient/src/contour_map.dart';
import 'package:contour_gradient/src/contour_shader.dart';
import 'package:contour_gradient/src/contour_strip.dart';
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
  // A border that strokes its own outline is masked until the map it is
  // shaded with is uploaded, which its second paint starts.
  for (int i = 0; i < 2; i++) {
    border.paint(
      Canvas(ui.PictureRecorder()),
      Offset(pad, pad) & size,
      textDirection: TextDirection.ltr,
    );
  }
  await contourMapsUploaded();
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

/// A [BeveledRectangleBorder] whose border is as wide as its side
/// everywhere, unlike Flutter's own, which is twice as wide.
///
/// Its outline is stroked with mitered corners and clipped to the side of the
/// outline that the stroke is aligned to.
class EvenBeveledBorder extends BeveledRectangleBorder {
  const EvenBeveledBorder({super.side, super.borderRadius});

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final Path outline = getOuterPath(rect, textDirection: textDirection);
    final Paint paint = Paint()
      ..color = side.color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;
    if (side.strokeAlign == BorderSide.strokeAlignCenter) {
      canvas.drawPath(outline, paint..strokeWidth = side.width);
      return;
    }
    assert(
      side.strokeAlign == BorderSide.strokeAlignInside ||
          side.strokeAlign == BorderSide.strokeAlignOutside,
    );
    final Path clip = side.strokeAlign == BorderSide.strokeAlignInside
        ? outline
        : (Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(rect.inflate(side.width * 2 + 1))
            ..addPath(outline, Offset.zero));
    canvas
      ..save()
      ..clipPath(clip)
      ..drawPath(outline, paint..strokeWidth = side.width * 2)
      ..restore();
  }
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
  setUpAll(() async {
    await loadContourShader();
    expect(contourShader(), isNotNull, reason: 'the shader must load');
  });

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
      // canvas is moved instead. Flutter's own BeveledRectangleBorder is
      // twice as wide as its side, so it is compared with the band between
      // its outlines.
      final Pixels expected = await render(
        shape is BeveledRectangleBorder
            ? EvenBeveledBorder(borderRadius: shape.borderRadius, side: side)
            : shape.copyWith(side: side),
        size,
        atOrigin: shape is LinearBorder,
      );
      final Pixels actual = await render(
        ContourGradientBorder(colors: colors, shape: shape, side: side),
        size,
      );
      // Borders whose outline is a rounded rectangle, beveled borders and
      // linear borders are clipped to their area rather than masked by the
      // shape's own border. Where the engine
      // flattens the curves of the clip, its edge can lie a fraction of a
      // pixel from the shape's, so a pixel is compared with the range of
      // coverages of the expected pixels around it. That the clip leaves no
      // pixel out is tested against the area of the border instead.
      final bool clipped =
          shape.runtimeType == RoundedRectangleBorder ||
          shape.runtimeType == StadiumBorder ||
          shape is BeveledRectangleBorder ||
          shape is LinearBorder ||
          (shape.runtimeType == CircleBorder &&
              (shape as CircleBorder).eccentricity == 0);
      int distanceFromNeighbours(int i, int alpha) {
        final int x = i % expected.width;
        final int y = i ~/ expected.width;
        int low = 255;
        int high = 0;
        for (
          int ny = math.max(0, y - 1);
          ny <= math.min(expected.height - 1, y + 1);
          ny++
        ) {
          for (
            int nx = math.max(0, x - 1);
            nx <= math.min(expected.width - 1, x + 1);
            nx++
          ) {
            final int neighbour = expected.alphaAt(ny * expected.width + nx);
            low = math.min(low, neighbour);
            high = math.max(high, neighbour);
          }
        }
        return math.max(0, math.max(low - alpha, alpha - high));
      }

      int maxDiff = 0;
      for (int i = 0; i < expected.width * expected.height; i++) {
        final int e = expected.alphaAt(i);
        final int a = actual.alphaAt(i);
        // A pixel on the edge of the shape in both is not missing or extra.
        // Its coverage can differ a little: the gradient is masked in a
        // layer, and some versions of the engine anti-alias a shape
        // differently depending on where the layer starts.
        if (e > 0 && e < 255 && a > 0 && a < 255) {
          continue;
        }
        final int diff = clipped ? distanceFromNeighbours(i, a) : (e - a).abs();
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
            // No pixel may be missing or extra.
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

    test('a rounded border covers exactly its area', () async {
      double area(RRect r) =>
          r.width * r.height -
          (1 - math.pi / 4) *
              (r.tlRadiusX * r.tlRadiusY +
                  r.trRadiusX * r.trRadiusY +
                  r.brRadiusX * r.brRadiusY +
                  r.blRadiusX * r.blRadiusY);
      const Size size = Size(140, 90);
      final Rect rect = Offset.zero & size;
      final Map<String, (OutlinedBorder, RRect)> shapes =
          <String, (OutlinedBorder, RRect)>{
            'rounded rectangle': (
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              RRect.fromRectAndRadius(rect, const Radius.circular(16)),
            ),
            'stadium': (
              const StadiumBorder(),
              RRect.fromRectAndRadius(rect, const Radius.circular(45)),
            ),
            'circle': (
              const CircleBorder(),
              RRect.fromRectAndRadius(
                Rect.fromCircle(center: rect.center, radius: 45),
                const Radius.circular(45),
              ),
            ),
          };
      for (final MapEntry<String, (OutlinedBorder, RRect)> shape
          in shapes.entries) {
        for (final double align in aligns.values) {
          for (final double width in widths) {
            final BorderSide side = BorderSide(
              width: width,
              strokeAlign: align,
            );
            final (OutlinedBorder border, RRect outline) = shape.value;
            final Pixels pixels = await render(
              ContourGradientBorder(
                colors: const <Color>[red, red],
                shape: border,
                side: side,
              ),
              size,
            );
            double covered = 0;
            for (int i = 0; i < pixels.width * pixels.height; i++) {
              covered += pixels.alphaAt(i) / 255;
            }
            final double expected =
                area(outline.inflate(side.strokeOutset)) -
                area(outline.deflate(side.strokeInset));
            // The clip's anti-aliased edges are off by a few hundredths of a
            // pixel, which adds up to a few percent on a thin border.
            expect(
              covered,
              closeTo(expected, expected * 0.04),
              reason: '${shape.key}, width $width, strokeAlign $align',
            );
          }
        }
      }
    });

    test('a bevel whose sides are short', () async {
      for (final double align in aligns.values) {
        expect(
          await maxAlphaDifference(
            const BeveledRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            const Size(31.3, 20.85),
            BorderSide(color: red, width: 3, strokeAlign: align),
            const <Color>[red, red],
          ),
          lessThanOrEqualTo(40),
          reason: 'strokeAlign $align',
        );
      }
    });

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

    test('a beveled border is as wide as its side', () async {
      const Size size = Size(120, 80);
      const BorderRadius radius = BorderRadius.all(Radius.circular(12));
      // How wide the border is where it runs through [from] in [direction]:
      // the coverage of the pixels on a line across it, added up every 0.05,
      // and averaged over lines up to 4 either side of [from]. Unlike
      // counting covered pixels, this also measures diagonal edges, whose
      // pixels are only partly covered.
      double widthAt(Pixels pixels, Offset from, Offset direction) {
        final Offset across = Offset(-direction.dy, direction.dx);
        double sum = 0;
        int lines = 0;
        for (double s = -4; s <= 4; s += 0.25) {
          lines++;
          for (double t = -10; t < 10; t += 0.05) {
            final Offset p = from + direction * s + across * t;
            sum += pixels.at(p.dx, p.dy).a * 0.05;
          }
        }
        return sum / lines;
      }

      for (final double align in aligns.values) {
        final Pixels pixels = await render(
          ContourGradientBorder(
            colors: const <Color>[red, blue],
            shape: const BeveledRectangleBorder(borderRadius: radius),
            side: BorderSide(width: 4, strokeAlign: align),
          ),
          size,
        );
        // Across the middle of the top side, and across the middle of the
        // top-left bevel, which runs from (0, 12) to (12, 0).
        expect(
          widthAt(pixels, const Offset(60, 0), const Offset(1, 0)),
          closeTo(4, 0.25),
          reason: 'side, strokeAlign $align',
        );
        expect(
          widthAt(pixels, const Offset(6, 6), const Offset(1, -1) / math.sqrt2),
          closeTo(4, 0.25),
          reason: 'bevel, strokeAlign $align',
        );
      }
    });

    test(
      'translucent colors do not build up where the band overlaps',
      () async {
        const Color faded = Color(0x80FF0000);
        for (final OutlinedBorder shape in <OutlinedBorder>[
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          const CircleBorder(),
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

    test('runs clockwise from the top-left corner', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(colors: <Color>[red, blue], side: side),
        size,
      );
      expect(pixels.at(50, 5), isColorCloseTo(lerpAt(0.125)));
      expect(pixels.at(95, 50), isColorCloseTo(lerpAt(0.375)));
      expect(pixels.at(50, 95), isColorCloseTo(lerpAt(0.625)));
      expect(pixels.at(5, 50), isColorCloseTo(lerpAt(0.875)));
    });

    test('ends in the last color without blending back to the first', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(colors: <Color>[red, blue], side: side),
        size,
      );
      // The gradient starts halfway around the top-left corner, at 45 degrees.
      // Just before that point the border is almost blue, just after it
      // almost red.
      expect(pixels.at(9, 14), isColorCloseTo(blue, tolerance: 0.1));
      expect(pixels.at(14, 9), isColorCloseTo(red, tolerance: 0.1));
    });

    test(
      'spaces colors evenly and blends back into a repeated first color',
      () async {
        // The centre line is 360 long. The four colors are spaced evenly, so
        // the gaps between them are 120 long, and red, at both ends, joins up
        // with itself across the start: each of the three colors gets 120.
        const Color green = Color(0xFF00FF00);
        final Pixels pixels = await render(
          const ContourGradientBorder(
            colors: <Color>[red, blue, green, red],
            side: side,
          ),
          size,
        );
        expect(pixels.at(65, 5), isColorCloseTo(Color.lerp(red, blue, 0.5)!));
        expect(pixels.at(95, 35), isColorCloseTo(blue));
        expect(pixels.at(35, 95), isColorCloseTo(green));
        expect(pixels.at(5, 65), isColorCloseTo(Color.lerp(green, red, 0.5)!));
      },
    );

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
      // The colors move a quarter of the way round, clockwise: the middle of
      // the top side, 0.125 of the way round, now has the color that was a
      // quarter of the way before it, which comes round from 0.875.
      expect(pixels.at(50, 5), isColorCloseTo(lerpAt(0.875)));
      // The middle of the left side, 0.875 of the way round.
      expect(pixels.at(5, 50), isColorCloseTo(lerpAt(0.625)));
    });

    test('startOffsets a whole number apart look the same', () async {
      Future<Pixels> withOffset(double offset) => render(
        ContourGradientBorder(
          colors: const <Color>[red, blue],
          startOffset: offset,
          side: side,
        ),
        size,
      );
      final Pixels expected = await withOffset(0.25);
      for (final double offset in <double>[1.25, 7.25, -0.75]) {
        final Pixels pixels = await withOffset(offset);
        for (final Offset p in const <Offset>[
          Offset(50, 5),
          Offset(95, 50),
          Offset(50, 95),
          Offset(5, 50),
        ]) {
          expect(
            pixels.at(p.dx, p.dy),
            isColorCloseTo(expected.at(p.dx, p.dy), tolerance: 0.01),
            reason: 'startOffset $offset at $p',
          );
        }
      }
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
      // 15 + 180 = 195, t = 0.232, before the first stop, where the border
      // is still the first color.
      expect(pixels.at(200, 5), isColorCloseTo(red));
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

    test('mitered bands place colors like rounded rectangles', () async {
      // A beveled rectangle without bevels is a rectangle, but its band is
      // built from its corners rather than as a rounded rectangle.
      const List<Color> colors = <Color>[red, blue, Color(0xFF00FF00), red];
      final Pixels direct = await render(
        const ContourGradientBorder(colors: colors, side: side),
        size,
      );
      final Pixels mitered = await render(
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
          mitered.at(x, y),
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

    test('separate LinearBorder edges each run the whole gradient', () async {
      final Pixels pixels = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue],
          shape: LinearBorder(
            top: LinearBorderEdge(),
            bottom: LinearBorderEdge(),
          ),
          side: side,
        ),
        size,
      );
      // Both lines run left to right, from x = -1 to 101, like an underline.
      for (final double x in <double>[2, 25, 50, 75, 97]) {
        final Color expected = lerpAt((x + 1.5) / 102);
        expect(pixels.at(x, 5), isColorCloseTo(expected), reason: 'top, $x');
        expect(
          pixels.at(x, 95),
          isColorCloseTo(expected),
          reason: 'bottom, $x',
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

  test('shaded borders look like masked ones', () async {
    const List<Color> colors = <Color>[
      Color(0xFF7F00FF),
      Color(0xFF00C6FF),
      Color(0xFFFF4E50),
      Color(0xFF7F00FF),
    ];
    for (final OutlinedBorder shape in <OutlinedBorder>[
      const StarBorder(innerRadiusRatio: 0.45),
      const OvalBorder(),
      const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
      const ContinuousRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(40)),
      ),
    ]) {
      for (final double offset in <double>[0, 0.3, -1.6]) {
        final ContourGradientBorder border = ContourGradientBorder(
          colors: colors,
          startOffset: offset,
          shape: shape,
          side: const BorderSide(width: 6),
        );
        final Pixels shaded = await render(border, const Size(140, 110));
        debugDisableContourShader = true;
        final Pixels masked = await render(border, const Size(140, 110));
        debugDisableContourShader = false;
        int worst = 0;
        for (int i = 0; i < shaded.data.lengthInBytes; i++) {
          worst = math.max(
            worst,
            (shaded.data.getUint8(i) - masked.data.getUint8(i)).abs(),
          );
        }
        expect(worst, lessThanOrEqualTo(24), reason: '$shape at $offset');
      }
    }
  });

  group('layers', () {
    // Counts the layers a border paints with, and passes everything else on
    // to a real canvas.
    int layersOf(
      OutlinedBorder shape, {
      double width = 3,
      Rect rect = const Rect.fromLTWH(10, 10, 140, 90),
    }) {
      final _LayerCountingCanvas canvas = _LayerCountingCanvas(
        Canvas(ui.PictureRecorder()),
      );
      ContourGradientBorder(
        colors: const <Color>[red, blue],
        shape: shape,
        side: BorderSide(width: width),
      ).paint(canvas, rect, textDirection: TextDirection.ltr);
      return canvas.layers;
    }

    const List<OutlinedBorder> stroked = <OutlinedBorder>[
      StarBorder(),
      OvalBorder(),
      CircleBorder(eccentricity: 0.5),
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      ContinuousRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ];

    test('are not used by shapes that can be clipped', () {
      for (final OutlinedBorder shape in <OutlinedBorder>[
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        const StadiumBorder(),
        const CircleBorder(),
        const BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        const LinearBorder(bottom: LinearBorderEdge()),
        const LinearBorder(
          start: LinearBorderEdge(),
          end: LinearBorderEdge(),
          top: LinearBorderEdge(),
          bottom: LinearBorderEdge(),
        ),
      ]) {
        expect(layersOf(shape), 0, reason: '$shape');
      }
    });

    test('are not used by shapes that stroke their border', () async {
      for (final OutlinedBorder shape in stroked) {
        layersOf(shape);
        layersOf(shape);
        await contourMapsUploaded();
        expect(layersOf(shape), 0, reason: '$shape');
      }
    });

    test('are used by shapes that stroke their border until their map is '
        'ready', () async {
      for (final OutlinedBorder shape in stroked) {
        expect(
          layersOf(shape, rect: const Rect.fromLTWH(0, 0, 141, 91)),
          2,
          reason: '$shape',
        );
      }
    });

    test('are used by a border painted only once at its size', () async {
      const Rect rect = Rect.fromLTWH(0, 0, 143, 93);
      layersOf(const StarBorder(), rect: rect);
      await contourMapsUploaded();
      // No map was built for the first paint, so the second one is masked
      // too, and starts building it.
      expect(layersOf(const StarBorder(), rect: rect), 2);
      await contourMapsUploaded();
      expect(layersOf(const StarBorder(), rect: rect), 0);
    });

    test('are used by shapes that stroke their border without the shader', () {
      debugDisableContourShader = true;
      addTearDown(() => debugDisableContourShader = false);
      for (final OutlinedBorder shape in stroked) {
        expect(layersOf(shape), 2, reason: '$shape');
      }
    });

    test('are used by a border too large for a map', () async {
      // 2400 by 2400 pixels at the tests' device pixel ratio of 3.
      const Rect huge = Rect.fromLTWH(0, 0, 800, 800);
      layersOf(const StarBorder(), rect: huge);
      layersOf(const StarBorder(), rect: huge);
      await contourMapsUploaded();
      expect(layersOf(const StarBorder(), rect: huge), 2);
    });

    test('are used by subclasses of shapes that stroke their border', () async {
      layersOf(const _StarSubclass());
      layersOf(const _StarSubclass());
      await contourMapsUploaded();
      expect(layersOf(const _StarSubclass()), 2);
    });

    test('are not used by a bevel whose sides are short', () {
      // Bevels of 10 leave the sides of this box under a pixel long, much
      // shorter than the border is wide.
      final _LayerCountingCanvas canvas = _LayerCountingCanvas(
        Canvas(ui.PictureRecorder()),
      );
      const ContourGradientBorder(
        colors: <Color>[red, blue],
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        side: BorderSide(width: 3),
      ).paint(
        canvas,
        const Rect.fromLTWH(0, 0, 31.3, 20.85),
        textDirection: TextDirection.ltr,
      );
      expect(canvas.layers, 0);
    });

    test('are used by a bevel too thick for its box', () {
      expect(
        layersOf(
          const BeveledRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          width: 60,
        ),
        2,
      );
    });
  });

  group('ContourStrip.mitered', () {
    double polygonArea(List<Offset> points) {
      double area = 0;
      for (int k = 0; k < points.length; k++) {
        final Offset a = points[k];
        final Offset b = points[(k + 1) % points.length];
        area += a.dx * b.dy - a.dy * b.dx;
      }
      return area.abs() / 2;
    }

    // The total area of the strip's quads.
    double quadsArea(ContourStrip strip) {
      double area = 0;
      for (int k = 0; k < strip.outer.length - 1; k++) {
        area += polygonArea(<Offset>[
          strip.outer[k],
          strip.outer[k + 1],
          strip.inner[k + 1],
          strip.inner[k],
        ]);
      }
      return area;
    }

    // A rectangle with its top-left corner cut off, running anticlockwise.
    const List<Offset> polygon = <Offset>[
      Offset(0, 20),
      Offset(0, 100),
      Offset(150, 100),
      Offset(150, 0),
      Offset(20, 0),
    ];

    test('covers the band between its edges without overlapping', () {
      final ContourStrip strip = ContourStrip.mitered(polygon, halfWidth: 4)!;
      final List<Offset> outer = strip.outer.sublist(0, strip.outer.length - 1);
      final List<Offset> inner = strip.inner.sublist(0, strip.inner.length - 1);
      expect(
        quadsArea(strip),
        closeTo(polygonArea(outer) - polygonArea(inner), 1e-6),
      );
    });

    test('runs clockwise from the point nearest the top-left', () {
      final ContourStrip strip = ContourStrip.mitered(polygon, halfWidth: 4)!;
      final Offset start = (strip.outer.first + strip.inner.first) / 2;
      // The middle of the cut-off corner.
      expect(start.dx, closeTo(10, 1e-9));
      expect(start.dy, closeTo(10, 1e-9));
      // Clockwise on screen, the band heads right along the top next.
      final Offset next = (strip.outer[1] + strip.inner[1]) / 2;
      expect(next.dx, greaterThan(start.dx));
      expect(
        strip.length,
        closeTo(2 * 150 + 2 * 100 - 40 + 20 * math.sqrt2, 1e-9),
      );
    });

    test('drops edges too short to move that far', () {
      // A hexagon whose left and right sides are a pixel long.
      const List<Offset> hexagon = <Offset>[
        Offset(10, 0),
        Offset(30, 0),
        Offset(40, 10),
        Offset(40, 11),
        Offset(30, 21),
        Offset(10, 21),
        Offset(0, 11),
        Offset(0, 10),
      ];
      final List<Offset> moved = ContourStrip.offsetPolyline(hexagon, -3)!;
      // The sides close up where the bevels on either side of them meet.
      expect(moved[2], moved[3]);
      expect(moved[6], moved[7]);
      expect(moved[2].dx, closeTo(40.5 - 3 * math.sqrt2, 1e-9));
      expect(moved[2].dy, closeTo(10.5, 1e-9));
      // The other edges stay 3 inside the hexagon.
      expect(moved[0].dy, closeTo(3, 1e-9));
      expect(moved[4].dy, closeTo(18, 1e-9));
    });

    test('offsetPolyline is null where the polygon closes up', () {
      const List<Offset> square = <Offset>[
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ];
      expect(ContourStrip.offsetPolyline(square, -4), isNotNull);
      expect(ContourStrip.offsetPolyline(square, -6), isNull);
    });

    test('is null where the band would turn inside out', () {
      expect(ContourStrip.mitered(polygon, halfWidth: 60), isNull);
    });
  });

  group('band cache', () {
    void paint(ShapeBorder border, Rect rect) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      border.paint(Canvas(recorder), rect, textDirection: TextDirection.ltr);
      recorder.endRecording().dispose();
    }

    setUp(contourBandCache.clear);

    test('reuses the band while only the gradient changes', () {
      const ContourGradientBorder border = ContourGradientBorder(
        colors: <Color>[red, blue],
        shape: StarBorder(),
        side: BorderSide(width: 4),
      );
      const Rect rect = Rect.fromLTWH(0, 0, 90, 90);
      paint(border, rect);
      expect(contourBandCache.length, 1);
      paint(border.copyWith(startOffset: 0.5), rect);
      paint(
        border.copyWith(colors: <Color>[blue, red, blue], startOffset: 0.7),
        rect.shift(const Offset(40, 25)),
      );
      expect(contourBandCache.length, 1);
      paint(border, const Rect.fromLTWH(0, 0, 80, 90));
      paint(border.copyWith(side: const BorderSide(width: 5)), rect);
      expect(contourBandCache.length, 3);
    });

    test('discards the least recently used band when full', () {
      final List<String> built = <String>[];
      final List<String> discarded = <String>[];
      final LruCache<String, String> cache = LruCache<String, String>(
        2,
        discarded.add,
      );
      String build(String key) {
        built.add(key);
        return key;
      }

      cache.get('a', () => build('a'));
      cache.get('b', () => build('b'));
      cache.get('a', () => build('a'));
      cache.get('c', () => build('c'));
      cache.get('a', () => build('a'));
      cache.get('b', () => build('b'));
      expect(built, <String>['a', 'b', 'c', 'b']);
      expect(discarded, <String>['b', 'c']);
      expect(cache.length, 2);
      cache.clear();
      expect(discarded, <String>['b', 'c', 'a', 'b']);
      expect(cache.length, 0);
    });

    for (final MapEntry<String, OutlinedBorder> shape
        in const <String, OutlinedBorder>{
          'rounded rectangle': RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          'star': StarBorder(innerRadiusRatio: 0.5),
        }.entries) {
      test('a ${shape.key} paints the same wherever its box is', () async {
        final ContourGradientBorder border = ContourGradientBorder(
          colors: const <Color>[red, blue, Color(0xFF00FF00)],
          startOffset: 0.3,
          shape: shape.value,
          side: const BorderSide(width: 6),
        );
        const Size size = Size(90, 70);
        final Pixels near = await render(border, size);
        // The band built for the first box is reused for this one.
        final Pixels far = await render(border, size, pad: 37);
        expect(contourBandCache.length, 1);
        // Up to a step of rounding, where the gradient image is filtered.
        for (double y = -8; y < size.height + 8; y++) {
          for (double x = -8; x < size.width + 8; x++) {
            expect(
              far.at(x, y),
              isColorCloseTo(near.at(x, y), tolerance: 1.5 / 255),
              reason: 'at ($x, $y)',
            );
          }
        }
      });
    }
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
      // Sampled at the union of both gradients' stops: 0.2 and 0.8 from one,
      // halves from the other's three even colors.
      final List<double> midStops = mid.stops!;
      expect(midStops.length, 5);
      for (final (int i, double stop) in <(int, double)>[
        (0, 0.0),
        (1, 0.2),
        (2, 0.5),
        (3, 0.8),
        (4, 1.0),
      ]) {
        expect(midStops[i], closeTo(stop, 1e-9));
      }

      final ContourGradientBorder start =
          ShapeBorder.lerp(border, other, 0.0)! as ContourGradientBorder;
      final List<double> stops = start.stops!;
      for (int i = 0; i < stops.length; i++) {
        expect(
          start.colors[i],
          isColorCloseTo(
            colorAt(border.colors, border.stops!, stops[i]),
            tolerance: 1e-6,
          ),
        );
      }
    });

    test('lerp keeps evenly spaced colors evenly spaced', () {
      // Buttons and chips animate every change to their shape, so they paint
      // lerped borders; these must look like the borders they come from, and
      // a repeated first color must still blend back into itself.
      const ContourGradientBorder even = ContourGradientBorder(
        colors: <Color>[red, blue, Color(0xFF00FF00), red],
      );
      final ContourGradientBorder mid =
          ShapeBorder.lerp(even, even.copyWith(startOffset: 0.5), 0.5)!
              as ContourGradientBorder;
      expect(mid.colors, even.colors);
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
          colors: <Color>[red, blue, red],
          borderSide: BorderSide(width: 2),
        ),
        gapExtent: 40,
      );
      // The gap runs from x = 8 to 8 + 40 + 8 = 56 along the top.
      expect(pixels.at(30, 0.5).a, 0.0);
      expect(pixels.at(100, 0.5).a, 1.0);
      // Red, blue and red with even stops: blue is halfway round, at the
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

  group('withGradient', () {
    test('keeps the shape and its side', () {
      const RoundedRectangleBorder shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(width: 3),
      );
      final ContourGradientBorder border = shape.withGradient(
        <Color>[red, blue],
        stops: <double>[0.2, 0.8],
        startOffset: 0.1,
      );
      expect(border.shape, shape);
      expect(border.side, shape.side);
      expect(border.colors, <Color>[red, blue]);
      expect(border.stops, <double>[0.2, 0.8]);
      expect(border.startOffset, 0.1);
    });

    test('paints like the constructor', () async {
      const Size size = Size(100, 60);
      final Pixels extension = await render(
        const StarBorder(
          side: BorderSide(width: 4),
        ).withGradient(<Color>[red, blue, red]),
        size,
      );
      final Pixels constructor = await render(
        const ContourGradientBorder(
          colors: <Color>[red, blue, red],
          shape: StarBorder(),
          side: BorderSide(width: 4),
        ),
        size,
      );
      expect(
        extension.data.buffer.asUint8List(),
        constructor.data.buffer.asUint8List(),
      );
    });

    testWidgets('lets a button apply its side', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder().withGradient(<Color>[red, blue]),
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
      expect((material.shape! as ContourGradientBorder).side.width, 3);
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

/// A canvas that counts [saveLayer] calls and passes every call on to
/// [canvas].
class _LayerCountingCanvas implements Canvas {
  _LayerCountingCanvas(this.canvas);

  final Canvas canvas;
  int layers = 0;

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    layers++;
    canvas.saveLayer(bounds, paint);
  }

  @override
  void save() => canvas.save();

  @override
  void restore() => canvas.restore();

  @override
  int getSaveCount() => canvas.getSaveCount();

  @override
  void translate(double dx, double dy) => canvas.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => canvas.scale(sx, sy);

  @override
  void transform(Float64List matrix4) => canvas.transform(matrix4);

  @override
  Float64List getTransform() => canvas.getTransform();

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      canvas.clipPath(path, doAntiAlias: doAntiAlias);

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => canvas.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) =>
      canvas.drawVertices(vertices, blendMode, paint);

  @override
  void drawPath(Path path, Paint paint) => canvas.drawPath(path, paint);

  @override
  void drawRect(Rect rect, Paint paint) => canvas.drawRect(rect, paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => canvas.drawRRect(rrect, paint);

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) =>
      canvas.drawDRRect(outer, inner, paint);

  @override
  void drawOval(Rect rect, Paint paint) => canvas.drawOval(rect, paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      canvas.drawCircle(c, radius, paint);

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, Paint paint) =>
      canvas.drawRSuperellipse(rsuperellipse, paint);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A [StarBorder] that might paint differently.
class _StarSubclass extends StarBorder {
  const _StarSubclass();
}
