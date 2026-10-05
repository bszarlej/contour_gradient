import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'color_stops.dart';
import 'contour_band.dart';
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
/// Flutter accepts a shape. The easiest way to make one is to call
/// [ContourGradientShape.withGradient] on a shape, which keeps the shape's
/// own side:
///
/// ```dart
/// Container(
///   decoration: ShapeDecoration(
///     shape: const StadiumBorder(
///       side: BorderSide(width: 2),
///     ).withGradient([Colors.purple, Colors.orange]),
///   ),
/// )
/// ```
///
/// The constructor does the same, and can be `const`:
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
/// The geometry of a border depends only on its shape, side and size, not on
/// its gradient. It is built the first time a border of that shape, side and
/// size is painted, and reused after that, wherever the border is. Changing
/// [colors], [stops] or [startOffset], as in an animation, only changes how
/// the geometry is colored, which costs little.
///
/// Borders whose outline is a rounded rectangle ([RoundedRectangleBorder],
/// [StadiumBorder] and a circular [CircleBorder]) get geometry that follows
/// the outline exactly, which is quick to build. Other shapes get geometry
/// along their path, which takes longer to build, and is then masked by the
/// shape's own border. Either way, painting costs two [Canvas.saveLayer]
/// calls.
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
  /// If [stops] is null, the colors are spaced evenly from 0.0 to 1.0. If
  /// [stops] is given, the border is the first color before the first stop
  /// and the last color after the last stop.
  ///
  /// The gradient does not blend from the last color back into the first, so
  /// where its end meets its start, at 0.0 on a closed border, the colors
  /// change in a hard edge. To blend back instead, repeat the first color at
  /// the end of [colors]. With evenly spaced colors on a closed border, the
  /// repeated color joins up with itself across 0.0, so it takes up the same
  /// share of the border as each of the others.
  final List<double>? stops;

  /// How far the gradient is moved clockwise along the border, as a fraction
  /// of its length.
  ///
  /// The gradient wraps around, so 0.0 and 1.0 look the same. That makes this
  /// value suitable for an endlessly repeating animation. Repeat the first
  /// color at the end of [colors] so no hard edge travels along the border;
  /// see [stops].
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
    final ({List<Color> colors, List<double> stops}) gradient = lerpColorStops(
      a.colors,
      a.stops,
      b.colors,
      b.stops,
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
    final double bandScale = _roundScaleDown(scale);
    // How far the colored band reaches past the border, so that the border's
    // anti-aliased edge pixels are colored too.
    final double margin = 1.0 / math.min(1.0, bandScale);
    final RRect? outline = _rrectOutline(rect, textDirection);

    // The band does not depend on the gradient, so it is built once for each
    // shape and size, around a box at the origin, and reused while only the
    // gradient changes, as when startOffset is animated.
    final ContourBand? band = contourBandCache.get(
      _BandKey(
        shape,
        side.width,
        side.strokeAlign,
        rect.size,
        textDirection,
        bandScale,
      ),
      () => ContourBand.fromStrips(
        outline != null
            ? <ContourStrip>[_rrectStrip(outline.shift(-rect.topLeft), margin)]
            : _stripsAlongShape(
                Offset.zero & rect.size,
                textDirection,
                margin,
                bandScale,
              ),
      ),
    );
    if (band == null) {
      return;
    }
    // The band between two rounded rectangles has no gaps to fill.
    _paintMasked(
      canvas,
      rect,
      textDirection,
      band,
      margin,
      fillGaps: outline == null ? 1 / scale : 0,
    );
  }

  /// [scale] rounded down to a quarter of an octave, so that the band of a
  /// border whose scale changes a little, as in a zoom transition, is reused.
  /// Rounding down keeps the band at least as wide as it needs to be.
  static double _roundScaleDown(double scale) {
    final double quarters = (math.log(scale) / math.ln2 * 4 + 1e-9).floor() / 4;
    return math.pow(2, quarters).toDouble();
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

  /// Paints [band], built around a box at the origin, colored by this
  /// border's gradient and masked by the shape's own border around [rect], so
  /// the result covers exactly the pixels the shape would paint.
  ///
  /// If [fillGaps] is positive, copies of the band shifted by that much are
  /// painted underneath it.
  void _paintMasked(
    Canvas canvas,
    Rect rect,
    TextDirection? textDirection,
    ContourBand band,
    double margin, {
    required double fillGaps,
  }) {
    // The layers must have bounds: a layer that masks with BlendMode.dstIn
    // cannot be shrunk to what is drawn in it, so without bounds it covers
    // the whole screen.
    final Rect bounds = band.bounds.shift(rect.topLeft).inflate(margin);
    // Where the band overlaps itself, at corners, the last quad wins instead
    // of blending, so translucent colors stay even. The band has no vertex
    // colors; BlendMode.src in drawVertices makes sure only the shader is
    // used.
    final Paint paint = Paint()
      ..blendMode = BlendMode.src
      ..shader = band.shader(
        colors,
        resolveStops(colors.length, stops),
        startOffset,
      );
    canvas
      ..saveLayer(bounds, Paint())
      ..save()
      ..translate(rect.left, rect.top);
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
          ..drawVertices(band.vertices, BlendMode.src, paint)
          ..restore();
      }
    }
    canvas
      ..drawVertices(band.vertices, BlendMode.src, paint)
      ..restore()
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
  ///
  /// [BeveledRectangleBorder.paint] strokes both the outer and the inner
  /// outline of its border with the side's width, which makes the border
  /// twice as wide, and its outlines are closer together on the bevels than
  /// on the sides. The band between two outlines that are the same distance
  /// apart everywhere is filled here instead.
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
    if (shape is BeveledRectangleBorder) {
      final List<Offset> outline = _beveledOutline(
        shape.borderRadius.resolve(textDirection).toRRect(rect),
      );
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addPolygon(_offsetPolygon(outline, side.strokeOutset), true)
          ..addPolygon(_offsetPolygon(outline, -side.strokeInset), true),
        Paint()..color = color,
      );
      return;
    }
    shape
        .copyWith(side: side.copyWith(color: color))
        .paint(canvas, rect, textDirection: textDirection);
  }

  /// The corners of the outline of a [BeveledRectangleBorder] around [rrect],
  /// clockwise from the top of the left side, as the border computes them.
  /// Corners that coincide are only listed once.
  static List<Offset> _beveledOutline(RRect rrect) {
    final Offset c = rrect.center;
    double r(double radius) => math.max(0.0, radius);
    final List<Offset> corners = <Offset>[
      Offset(rrect.left, math.min(c.dy, rrect.top + r(rrect.tlRadiusY))),
      Offset(math.min(c.dx, rrect.left + r(rrect.tlRadiusX)), rrect.top),
      Offset(math.max(c.dx, rrect.right - r(rrect.trRadiusX)), rrect.top),
      Offset(rrect.right, math.min(c.dy, rrect.top + r(rrect.trRadiusY))),
      Offset(rrect.right, math.max(c.dy, rrect.bottom - r(rrect.brRadiusY))),
      Offset(math.max(c.dx, rrect.right - r(rrect.brRadiusX)), rrect.bottom),
      Offset(math.min(c.dx, rrect.left + r(rrect.blRadiusX)), rrect.bottom),
      Offset(rrect.left, math.max(c.dy, rrect.bottom - r(rrect.blRadiusY))),
    ];
    final List<Offset> distinct = <Offset>[];
    for (final Offset p in corners) {
      if (distinct.isEmpty || (p - distinct.last).distanceSquared > 1e-12) {
        distinct.add(p);
      }
    }
    while (distinct.length > 1 &&
        (distinct.first - distinct.last).distanceSquared <= 1e-12) {
      distinct.removeLast();
    }
    return distinct;
  }

  /// Moves every edge of the convex, clockwise polygon [points] outwards by
  /// [distance], or inwards if it is negative, and returns where the moved
  /// edges meet.
  static List<Offset> _offsetPolygon(List<Offset> points, double distance) {
    final int n = points.length;
    if (n < 3 || distance == 0) {
      return points;
    }
    // The outward normal of each edge.
    final List<Offset> normals = <Offset>[
      for (int i = 0; i < n; i++)
        () {
          final Offset e = points[(i + 1) % n] - points[i];
          return Offset(e.dy, -e.dx) / e.distance;
        }(),
    ];
    return <Offset>[
      for (int i = 0; i < n; i++)
        () {
          final Offset a = normals[(i - 1 + n) % n];
          final Offset b = normals[i];
          // The moved edges meet on the bisector of the two normals.
          final double dot = a.dx * b.dx + a.dy * b.dy;
          return points[i] + (a + b) * (distance / (1 + dot));
        }(),
    ];
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

  /// The factor by which lengths on [canvas] are scaled on the screen.
  ///
  /// That is the scale of the canvas' current transform times the device
  /// pixel ratio. The device pixel ratio is not part of the canvas' transform:
  /// the root layer of the view applies it, above the picture being recorded.
  static double _scaleOf(Canvas canvas) {
    final Float64List m = canvas.getTransform();
    final double scale =
        math.sqrt((m[0] * m[5] - m[1] * m[4]).abs()) * _devicePixelRatio;
    return scale > 0 && scale.isFinite ? scale : 1.0;
  }

  /// The device pixel ratio of the views the border may be painted in.
  ///
  /// A border cannot tell which view it is painted in, so if there are
  /// several, this is the largest ratio, which is fine enough for all of
  /// them.
  static double get _devicePixelRatio {
    double ratio = 0;
    for (final ui.FlutterView view in ui.PlatformDispatcher.instance.views) {
      ratio = math.max(ratio, view.devicePixelRatio);
    }
    return ratio > 0 ? ratio : 1.0;
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

/// Everything the band of a [ContourGradientBorder] depends on.
@immutable
class _BandKey {
  const _BandKey(
    this.shape,
    this.width,
    this.strokeAlign,
    this.size,
    this.textDirection,
    this.scale,
  );

  final OutlinedBorder shape;
  final double width;
  final double strokeAlign;
  final Size size;
  final TextDirection? textDirection;
  final double scale;

  @override
  bool operator ==(Object other) {
    return other is _BandKey &&
        other.width == width &&
        other.strokeAlign == strokeAlign &&
        other.size == size &&
        other.textDirection == textDirection &&
        other.scale == scale &&
        other.shape == shape;
  }

  @override
  int get hashCode =>
      Object.hash(shape, width, strokeAlign, size, textDirection, scale);
}

/// Paints any [OutlinedBorder] with a gradient that runs along the border.
extension ContourGradientShape on OutlinedBorder {
  /// Returns a [ContourGradientBorder] shaped like this border, painted with
  /// [colors] along its length.
  ///
  /// The border keeps its own [OutlinedBorder.side], whose color is replaced
  /// by the gradient. Like any Flutter shape, it paints nothing unless it has
  /// a side, or the widget it is given to applies one, as `OutlinedButton`
  /// and `Chip` do.
  ///
  /// ```dart
  /// Card(
  ///   shape: const RoundedRectangleBorder(
  ///     borderRadius: BorderRadius.all(Radius.circular(16)),
  ///     side: BorderSide(width: 2),
  ///   ).withGradient([Colors.purple, Colors.orange]),
  /// )
  /// ```
  ///
  /// See [ContourGradientBorder.colors], [ContourGradientBorder.stops] and
  /// [ContourGradientBorder.startOffset]. Use the [ContourGradientBorder]
  /// constructor instead where the border must be `const`.
  ContourGradientBorder withGradient(
    List<Color> colors, {
    List<double>? stops,
    double startOffset = 0.0,
  }) {
    return ContourGradientBorder(
      colors: colors,
      stops: stops,
      startOffset: startOffset,
      shape: this,
      side: side,
    );
  }
}
