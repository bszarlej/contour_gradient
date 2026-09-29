import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'color_stops.dart';
import 'contour_strip.dart';

/// A border of any [OutlinedBorder] shape, painted with a gradient that runs
/// along the border itself.
///
/// Unlike a [SweepGradient] or the "gradient background with padding" trick,
/// the gradient follows the length of the border: a color stop at 0.5 sits
/// exactly halfway around the border, whatever the shape of the box.
///
/// The outline comes from [shape], which can be any [OutlinedBorder]:
/// [RoundedRectangleBorder], [StadiumBorder], [CircleBorder], [OvalBorder],
/// [StarBorder], [BeveledRectangleBorder], [ContinuousRectangleBorder],
/// [RoundedSuperellipseBorder], [LinearBorder] or your own. The width and
/// alignment of the border come from [side]; the side of [shape] and the color
/// of [side] are ignored.
///
/// Position 0.0 of the gradient is the point of the outline nearest the
/// top-left corner of the box, and the gradient runs clockwise from there.
/// Use [startOffset] to move it; animating [startOffset] from 0.0 to 1.0
/// moves the gradient once around the border.
///
/// Because this is itself an [OutlinedBorder], it can be used anywhere
/// Flutter accepts a shape:
///
/// ```dart
/// Container(
///   decoration: const ShapeDecoration(
///     shape: ContourGradientBorder(
///       colors: [Colors.purple, Colors.orange],
///       shape: StadiumBorder(),
///       side: BorderSide(width: 2),
///     ),
///   ),
/// )
/// ```
///
/// ## Performance
///
/// Borders whose outline is a rounded rectangle ([RoundedRectangleBorder],
/// [StadiumBorder] and a circular [CircleBorder]) are painted directly. Other
/// shapes paint their own border into an offscreen layer that is used as a
/// mask for the gradient, which costs two [Canvas.saveLayer] calls.
class ContourGradientBorder extends OutlinedBorder {
  /// Creates a border shaped like [shape], painted with a gradient along its
  /// length.
  ///
  /// If [stops] is non-null, it must have the same length as [colors] and its
  /// values must be in the range 0.0 to 1.0, in ascending order.
  const ContourGradientBorder({
    required this.colors,
    this.stops,
    this.startOffset = 0.0,
    this.shape = const RoundedRectangleBorder(),
    super.side = const BorderSide(),
  });

  /// The colors the gradient takes along the border.
  ///
  /// Must not be empty. A single color paints a solid border.
  final List<Color> colors;

  /// Positions of [colors] along the border, as fractions of its length.
  ///
  /// On a closed border, the gradient wraps around: after the last color it
  /// blends back into the first, ending where it started. If [stops] is null,
  /// the colors are spaced evenly around the border, so each takes up the same
  /// share of it; there is no need to repeat the first color at the end. If
  /// [stops] is given, the stretch between the last stop and the first one,
  /// going round through 1.0, blends from the last color to the first.
  ///
  /// On an open border, such as some [LinearBorder]s, the gradient runs from
  /// the first color to the last without wrapping.
  final List<double>? stops;

  /// How far the gradient is moved clockwise along the border, as a fraction
  /// of its length.
  ///
  /// The gradient wraps around, so 0.0 and 1.0 look the same. That makes this
  /// value suitable for an endlessly repeating animation.
  final double startOffset;

  /// The shape of the border.
  ///
  /// Its [OutlinedBorder.side] is replaced by [side].
  final OutlinedBorder shape;

  /// [shape] with this border's [side].
  OutlinedBorder get _shape => shape.copyWith(side: side);

  @override
  EdgeInsetsGeometry get dimensions => _shape.dimensions;

  @override
  ContourGradientBorder scale(double t) {
    final ShapeBorder scaled = shape.scale(t);
    return ContourGradientBorder(
      colors: colors,
      stops: stops,
      startOffset: startOffset,
      shape: scaled is OutlinedBorder ? scaled : shape,
      side: side.scale(t),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    final ContourGradientBorder? from = _asContourGradientBorder(a);
    if (from != null) {
      return _lerp(from, this, t);
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    final ContourGradientBorder? to = _asContourGradientBorder(b);
    if (to != null) {
      return _lerp(this, to, t);
    }
    return super.lerpTo(b, t);
  }

  /// Converts borders that this one knows how to animate from or to. Any
  /// other [OutlinedBorder] becomes a gradient border of a single color.
  static ContourGradientBorder? _asContourGradientBorder(ShapeBorder? border) {
    return switch (border) {
      final ContourGradientBorder b => b,
      final OutlinedBorder b => ContourGradientBorder(
        colors: <Color>[b.side.color],
        shape: b,
        side: b.side,
      ),
      _ => null,
    };
  }

  static ContourGradientBorder _lerp(
    ContourGradientBorder a,
    ContourGradientBorder b,
    double t,
  ) {
    // The result has explicit stops, which would no longer wrap around the
    // way evenly spaced colors do. So both gradients are wrapped first, as
    // paint does for closed borders. On an open border, such as some
    // LinearBorders, the gradient ends in its first color while the border
    // animates.
    final ({List<Color> colors, List<double> stops}) from = wrapColorStops(
      a.colors,
      a.stops,
    );
    final ({List<Color> colors, List<double> stops}) to = wrapColorStops(
      b.colors,
      b.stops,
    );
    final ({List<Color> colors, List<double> stops}) gradient = lerpColorStops(
      from.colors,
      from.stops,
      to.colors,
      to.stops,
      t,
    );
    return ContourGradientBorder(
      colors: gradient.colors,
      stops: gradient.stops,
      startOffset: _lerpOffset(a.startOffset, b.startOffset, t),
      shape: OutlinedBorder.lerp(a.shape, b.shape, t)!,
      side: BorderSide.lerp(a.side, b.side, t),
    );
  }

  /// Interpolates between two start offsets the short way round.
  ///
  /// Offsets that differ by a whole number look the same, so going the long
  /// way would spin the gradient for no reason. That matters because widgets
  /// such as buttons and chips animate every change to their shape: with a
  /// repeating animation, each time it wraps from 1.0 back to 0.0 the
  /// gradient would spin backwards almost a full turn.
  static double _lerpOffset(double a, double b, double t) {
    final double delta = b - a;
    return a + (delta - delta.roundToDouble()) * t;
  }

  /// Returns a copy of this border with the given fields replaced with the
  /// new values.
  @override
  ContourGradientBorder copyWith({
    BorderSide? side,
    List<Color>? colors,
    List<double>? stops,
    double? startOffset,
    OutlinedBorder? shape,
  }) {
    return ContourGradientBorder(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      startOffset: startOffset ?? this.startOffset,
      shape: shape ?? this.shape,
      side: side ?? this.side,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _shape.getInnerPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _shape.getOuterPath(rect, textDirection: textDirection);
  }

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    _shape.paintInterior(canvas, rect, paint, textDirection: textDirection);
  }

  @override
  bool get preferPaintInterior => _shape.preferPaintInterior;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0 || colors.isEmpty) {
      return;
    }
    assert(_debugAssertValidStops());

    if (colors.length == 1) {
      _paintOutline(canvas, rect, textDirection, colors.single);
      return;
    }

    final double scale = _scaleOf(canvas);
    // How far the colored band reaches past the border, so that the border's
    // anti-aliased edge pixels are colored too.
    final double margin = 1.0 / math.min(1.0, scale);

    final RRect? outline = _rrectOutline(rect, textDirection);
    final List<ContourStrip> strips = outline != null
        ? <ContourStrip>[_rrectStrip(outline, margin)]
        : _stripsAlongShape(rect, textDirection, margin, scale);
    final ({ui.Vertices vertices, Rect bounds})? built = _buildVertices(strips);
    if (built == null) {
      return;
    }
    // The band between two rounded rectangles has no gaps to fill.
    _paintMasked(
      canvas,
      rect,
      textDirection,
      built,
      margin,
      fillGaps: outline == null ? 1 / scale : 0,
    );
    built.vertices.dispose();
  }

  /// Builds the triangles for [strips], with the gradient wrapped around if
  /// every strip is a closed loop.
  ({ui.Vertices vertices, Rect bounds})? _buildVertices(
    List<ContourStrip> strips,
  ) {
    final ({List<Color> colors, List<double> stops}) gradient =
        strips.every((ContourStrip s) => s.closed)
        ? wrapColorStops(colors, stops)
        : (colors: colors, stops: resolveStops(colors.length, stops));
    return ContourStrip.buildVertices(
      strips,
      colors: gradient.colors,
      stops: gradient.stops,
      startOffset: startOffset,
    );
  }

  /// The rounded rectangle the border is drawn around, for shapes whose
  /// border is exactly the band between two rounded rectangles.
  RRect? _rrectOutline(Rect rect, TextDirection? textDirection) {
    final OutlinedBorder shape = this.shape;
    // Exact type checks: a subclass might paint differently.
    if (shape.runtimeType == RoundedRectangleBorder) {
      return (shape as RoundedRectangleBorder).borderRadius
          .resolve(textDirection)
          .toRRect(rect);
    }
    if (shape.runtimeType == StadiumBorder) {
      return RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide / 2),
      );
    }
    if (shape.runtimeType == CircleBorder &&
        ((shape as CircleBorder).eccentricity == 0 ||
            rect.width == rect.height)) {
      final double radius = rect.shortestSide / 2;
      return RRect.fromRectAndRadius(
        Rect.fromCircle(center: rect.center, radius: radius),
        Radius.circular(radius),
      );
    }
    return null;
  }

  /// The band between two rounded rectangles that covers the border around
  /// [outline], reaching [margin] past it on either side.
  ///
  /// Unlike [ContourStrip.alongPath], it follows the border's exact outline,
  /// so its corners are colored along radial lines.
  ContourStrip _rrectStrip(RRect outline, double margin) {
    final RRect outer = outline.inflate(side.strokeOutset).scaleRadii();
    final RRect inner = _deflateClamped(outline, side.strokeInset);
    return ContourStrip.rrectRing(
      outer.inflate(margin).scaleRadii(),
      _deflateClamped(inner, margin),
    );
  }

  /// A band along the outline of [shape] around [rect], wide enough to cover
  /// its border.
  List<ContourStrip> _stripsAlongShape(
    Rect rect,
    TextDirection? textDirection,
    double margin,
    double scale,
  ) {
    // Most shapes stroke the outline of the rect inflated by half the stroke
    // offset. The band is made a full stroke width wide on either side, so it
    // also covers shapes that align their stroke differently. A
    // ContinuousRectangleBorder ignores the stroke's alignment and strokes
    // the outline of the rect itself, which differs by more than that at its
    // corners. A LinearBorder only gets a band along the edges it draws.
    final OutlinedBorder shape = this.shape;
    final Path centreLine = switch (shape) {
      LinearBorder() => _linearBorderLine(shape, rect, textDirection, margin),
      ContinuousRectangleBorder() => shape.getOuterPath(
        rect,
        textDirection: textDirection,
      ),
      _ => shape.getOuterPath(
        rect.inflate(side.strokeOffset / 2),
        textDirection: textDirection,
      ),
    };
    return ContourStrip.alongPath(
      centreLine,
      halfWidth: side.width + margin,
      step: 2.0 / scale,
    );
  }

  /// Paints the colored band [built], masked by the shape's own border, so
  /// the result covers exactly the pixels the shape would paint.
  ///
  /// If [fillGaps] is positive, copies of the band shifted by that much are
  /// painted underneath it.
  void _paintMasked(
    Canvas canvas,
    Rect rect,
    TextDirection? textDirection,
    ({ui.Vertices vertices, Rect bounds}) built,
    double margin, {
    required double fillGaps,
  }) {
    // The layers must have bounds: a layer that masks with BlendMode.dstIn
    // cannot be shrunk to what is drawn in it, so without bounds it covers
    // the whole screen.
    final Rect bounds = built.bounds.inflate(margin);
    // Where the band overlaps itself, at corners, the last quad wins instead
    // of blending, so translucent colors stay even.
    final Paint replace = Paint()..blendMode = BlendMode.src;
    canvas.saveLayer(bounds, Paint());
    // Where the band's pieces meet, as at the centre of a tight curve on a
    // thick border, gaps of a pixel or so can be left between them. Copies
    // shifted by a device pixel underneath fill them with the neighbouring
    // color.
    if (fillGaps > 0) {
      for (final Offset offset in <Offset>[
        Offset(fillGaps, 0),
        Offset(-fillGaps, 0),
        Offset(0, fillGaps),
        Offset(0, -fillGaps),
      ]) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..drawVertices(built.vertices, BlendMode.dst, replace)
          ..restore();
      }
    }
    canvas
      ..drawVertices(built.vertices, BlendMode.dst, replace)
      ..saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    _paintOutline(canvas, rect, textDirection, const Color(0xFF000000));
    canvas
      ..restore()
      ..restore();
  }

  /// Paints the border of [shape] around [rect] in a single [color].
  ///
  /// [LinearBorder.paint] draws each edge separately, so where two edges
  /// meet inside a pixel, a faint line shows between them. It also places
  /// some edges as if [rect] started at the origin. Its edges are filled as
  /// one path here instead.
  void _paintOutline(
    Canvas canvas,
    Rect rect,
    TextDirection? textDirection,
    Color color,
  ) {
    final OutlinedBorder shape = this.shape;
    if (shape is LinearBorder) {
      final Path path = Path();
      for (final Rect? edge in _linearBorderEdges(
        shape,
        rect.size,
        textDirection,
      )) {
        if (edge != null) {
          path.addRect(edge.shift(rect.topLeft));
        }
      }
      canvas.drawPath(path, Paint()..color = color);
      return;
    }
    shape
        .copyWith(side: side.copyWith(color: color))
        .paint(canvas, rect, textDirection: textDirection);
  }

  /// Where [LinearBorder.paint] puts each edge of [shape] around a box of
  /// [size] at the origin, clockwise from the top: top, right, bottom and
  /// left. Edges it does not draw are null.
  List<Rect?> _linearBorderEdges(
    LinearBorder shape,
    Size size,
    TextDirection? textDirection,
  ) {
    final bool rtl = textDirection == TextDirection.rtl;
    final double width = side.width;
    final LinearBorderEdge? left = rtl ? shape.end : shape.start;
    final LinearBorderEdge? right = rtl ? shape.start : shape.end;
    final double insetTop = shape.top == null ? 0.0 : width;
    final double insetBottom = shape.bottom == null ? 0.0 : width;

    Rect? horizontal(LinearBorderEdge? edge, double y) {
      if (edge == null || edge.size == 0.0) {
        return null;
      }
      final double length = size.width * edge.size;
      final double start = (size.width - length) * ((edge.alignment + 1) / 2);
      final double x = rtl ? size.width - start - length : start;
      return Rect.fromLTWH(x, y, length, width);
    }

    Rect? vertical(LinearBorderEdge? edge, double x) {
      if (edge == null || edge.size == 0.0) {
        return null;
      }
      final double available = size.height - insetTop - insetBottom;
      final double length = available * edge.size;
      final double y = (available - length) * ((edge.alignment + 1) / 2);
      return Rect.fromLTWH(x, y, width, length);
    }

    return <Rect?>[
      horizontal(shape.top, 0.0),
      vertical(right, size.width - (right == null ? 0.0 : width)),
      horizontal(shape.bottom, size.height - width),
      vertical(left, 0.0),
    ];
  }

  /// The line along the middle of the edges that [shape] draws around
  /// [rect], so that the gradient runs along those edges only.
  ///
  /// Edges that meet at a corner are joined into one line. Each line runs
  /// from its end nearest the top-left corner of [rect], and the lines are
  /// ordered by that end. If all four edges meet, they form a loop. The ends
  /// of each line are extended by [margin], to color the anti-aliased pixels
  /// at the ends of the edges.
  Path _linearBorderLine(
    LinearBorder shape,
    Rect rect,
    TextDirection? textDirection,
    double margin,
  ) {
    final double width = side.width;
    final Size size = rect.size;
    final double insetBottom = shape.bottom == null ? 0.0 : width;
    final List<Rect?> edges = _linearBorderEdges(shape, size, textDirection);

    // Each edge's centre line, running clockwise.
    List<Offset> ends(int i) {
      final Rect r = edges[i]!;
      return switch (i) {
        0 => <Offset>[r.centerLeft, r.centerRight],
        1 => <Offset>[r.topCenter, r.bottomCenter],
        2 => <Offset>[r.centerRight, r.centerLeft],
        _ => <Offset>[r.bottomCenter, r.topCenter],
      };
    }

    // Whether edge i and the next edge clockwise meet at their corner, and
    // where their centre lines cross.
    final double tolerance = width + 0.5;
    Offset? corner(int i) {
      final Rect? a = edges[i];
      final Rect? b = edges[(i + 1) % 4];
      if (a == null || b == null) {
        return null;
      }
      final bool meet = switch (i) {
        0 => a.right >= size.width - tolerance && b.top <= tolerance,
        1 =>
          a.bottom >= size.height - insetBottom - tolerance &&
              b.right >= size.width - tolerance,
        2 =>
          a.left <= tolerance &&
              b.bottom >= size.height - insetBottom - tolerance,
        _ => a.top <= tolerance && b.left <= tolerance,
      };
      if (!meet) {
        return null;
      }
      return switch (i) {
        0 => Offset(b.center.dx, a.center.dy),
        1 => Offset(a.center.dx, b.center.dy),
        2 => Offset(b.center.dx, a.center.dy),
        _ => Offset(a.center.dx, b.center.dy),
      };
    }

    final List<Offset?> corners = <Offset?>[
      for (int i = 0; i < 4; i++) corner(i),
    ];
    final Path path = Path();
    if (corners.every((Offset? c) => c != null)) {
      return path..addPolygon(<Offset>[
        for (final Offset? c in corners) c! + rect.topLeft,
      ], true);
    }

    final List<List<Offset>> lines = <List<Offset>>[];
    for (int i = 0; i < 4; i++) {
      // Start a line at each edge that does not continue one.
      if (edges[i] == null || corners[(i + 3) % 4] != null) {
        continue;
      }
      final List<Offset> points = <Offset>[ends(i).first];
      int j = i;
      while (corners[j] != null) {
        points.add(corners[j]!);
        j = (j + 1) % 4;
      }
      points.add(ends(j).last);
      lines.add(points);
    }

    double fromTopLeft(Offset p) => p.distanceSquared;
    for (final List<Offset> points in lines) {
      if (fromTopLeft(points.last) < fromTopLeft(points.first)) {
        points.setAll(0, points.reversed.toList());
      }
    }
    lines.sort(
      (List<Offset> a, List<Offset> b) =>
          fromTopLeft(a.first).compareTo(fromTopLeft(b.first)),
    );

    Offset extend(Offset end, Offset towards) {
      final Offset d = end - towards;
      final double length = d.distance;
      return length > 0 ? end + d * (margin / length) : end;
    }

    for (final List<Offset> points in lines) {
      points
        ..first = extend(points.first, points[1])
        ..last = extend(points.last, points[points.length - 2]);
      path.moveTo(points.first.dx + rect.left, points.first.dy + rect.top);
      for (final Offset p in points.skip(1)) {
        path.lineTo(p.dx + rect.left, p.dy + rect.top);
      }
    }
    return path;
  }

  bool _debugAssertValidStops() {
    final List<double>? stops = this.stops;
    if (stops == null) {
      return true;
    }
    if (stops.length != colors.length) {
      throw ArgumentError(
        'ContourGradientBorder: "stops" must have the same length as '
        '"colors" (${stops.length} stops for ${colors.length} colors).',
      );
    }
    for (int i = 0; i < stops.length; i++) {
      if (stops[i] < 0.0 ||
          stops[i] > 1.0 ||
          (i > 0 && stops[i] < stops[i - 1])) {
        throw ArgumentError(
          'ContourGradientBorder: "stops" must be in ascending order and in '
          'the range 0.0 to 1.0, but got $stops.',
        );
      }
    }
    return true;
  }

  /// Deflates [r] by [delta], without letting it turn inside out when [delta]
  /// is more than half its size.
  static RRect _deflateClamped(RRect r, double delta) {
    final double cx = (r.left + r.right) / 2;
    final double cy = (r.top + r.bottom) / 2;
    double radius(double value) => math.max(0, value - delta);
    return RRect.fromLTRBAndCorners(
      math.min(r.left + delta, cx),
      math.min(r.top + delta, cy),
      math.max(r.right - delta, cx),
      math.max(r.bottom - delta, cy),
      topLeft: Radius.elliptical(radius(r.tlRadiusX), radius(r.tlRadiusY)),
      topRight: Radius.elliptical(radius(r.trRadiusX), radius(r.trRadiusY)),
      bottomRight: Radius.elliptical(radius(r.brRadiusX), radius(r.brRadiusY)),
      bottomLeft: Radius.elliptical(radius(r.blRadiusX), radius(r.blRadiusY)),
    ).scaleRadii();
  }

  /// The factor by which the canvas' current transform scales lengths.
  static double _scaleOf(Canvas canvas) {
    final Float64List m = canvas.getTransform();
    final double scale = math.sqrt((m[0] * m[5] - m[1] * m[4]).abs());
    return scale > 0 && scale.isFinite ? scale : 1.0;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ContourGradientBorder &&
        other.side == side &&
        other.shape == shape &&
        other.startOffset == startOffset &&
        listEquals(other.colors, colors) &&
        listEquals(other.stops, stops);
  }

  @override
  int get hashCode => Object.hash(
    side,
    shape,
    startOffset,
    Object.hashAll(colors),
    stops == null ? null : Object.hashAll(stops!),
  );

  @override
  String toString() {
    return '${objectRuntimeType(this, 'ContourGradientBorder')}'
        '($side, $shape, colors: $colors, stops: $stops, '
        'startOffset: $startOffset)';
  }
}
