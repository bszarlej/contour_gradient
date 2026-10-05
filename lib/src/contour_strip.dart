import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A band that runs along a contour, described as matching pairs of points on
/// its outer and inner edge.
///
/// Consecutive pairs form the quads of the band. Colors are assigned by the
/// distance travelled along the band's centre line, so a gradient follows the
/// contour regardless of its shape.
///
/// This class only knows about geometry; [ContourBand] turns strips into
/// triangles that a gradient can be painted along.
class ContourStrip {
  ContourStrip._(this.outer, this.inner, this.distances, this.closed);

  /// Builds a strip from matching outer and inner points.
  ///
  /// [centres] are the points of the centre line that each pair belongs to.
  /// If null, the midpoints of the pairs are used.
  ///
  /// If [closed] is true, the last pair is connected back to the first.
  factory ContourStrip.fromPairs(
    List<Offset> outer,
    List<Offset> inner, {
    List<Offset>? centres,
    bool closed = true,
  }) {
    assert(outer.length == inner.length);
    assert(centres == null || centres.length == outer.length);
    assert(outer.isNotEmpty);
    final List<Offset> o = <Offset>[...outer, if (closed) outer.first];
    final List<Offset> i = <Offset>[...inner, if (closed) inner.first];
    Offset centre(int k) =>
        centres != null ? centres[k % centres.length] : (o[k] + i[k]) / 2;
    final List<double> distances = List<double>.filled(o.length, 0.0);
    for (int k = 1; k < o.length; k++) {
      distances[k] = distances[k - 1] + (centre(k) - centre(k - 1)).distance;
    }
    return ContourStrip._(o, i, distances, closed);
  }

  /// Builds the band between two rounded rectangles, where [inner] lies
  /// inside [outer].
  ///
  /// The band starts halfway around the top-left corner and runs clockwise.
  ///
  /// Corners are paired by angle, so on a corner where both radii are
  /// positive the colors change along radial lines. Where the inner corner is
  /// sharper than the outer one, the quads fan out from the inner corner,
  /// which gives sharp corners a mitered look.
  ///
  /// [tolerance] is the maximum distance, in logical pixels, between a curved
  /// corner and the straight segments that approximate it.
  factory ContourStrip.rrectRing(
    RRect outer,
    RRect inner, {
    double tolerance = 0.05,
  }) {
    final List<_Corner> oc = _Corner.of(outer);
    final List<_Corner> ic = _Corner.of(inner);
    final List<Offset> o = <Offset>[];
    final List<Offset> i = <Offset>[];

    void addPair(Offset outerPoint, Offset innerPoint) {
      if (o.isNotEmpty && o.last == outerPoint && i.last == innerPoint) {
        return;
      }
      o.add(outerPoint);
      i.add(innerPoint);
    }

    void addArc(int corner, double from, double to) {
      final double radius = math.max(
        math.max(oc[corner].rx, oc[corner].ry),
        math.max(ic[corner].rx, ic[corner].ry),
      );
      final int segments = radius <= 0
          ? 1
          : ((to - from) / math.sqrt(8 * tolerance / radius)).ceil().clamp(
              1,
              64,
            );
      for (int s = 0; s <= segments; s++) {
        final double angle = from + (to - from) * s / segments;
        addPair(oc[corner].at(angle), ic[corner].at(angle));
      }
    }

    // Adds the straight edge from the last pair to the start of the next
    // corner. Where one edge is longer than the other, the part they share is
    // split off so that it gets rectangular quads.
    void addEdge(int nextCorner, double nextAngle, Offset direction) {
      final Offset oStart = o.last;
      final Offset iStart = i.last;
      final Offset oEnd = oc[nextCorner].at(nextAngle);
      final Offset iEnd = ic[nextCorner].at(nextAngle);
      double along(Offset p) => p.dx * direction.dx + p.dy * direction.dy;
      final double from = math.max(along(oStart), along(iStart));
      final double to = math.min(along(oEnd), along(iEnd));
      if (to > from) {
        addPair(
          oStart + direction * (from - along(oStart)),
          iStart + direction * (from - along(iStart)),
        );
        addPair(
          oStart + direction * (to - along(oStart)),
          iStart + direction * (to - along(iStart)),
        );
      }
    }

    const double pi = math.pi;
    addArc(0, 1.25 * pi, 1.5 * pi);
    addEdge(1, 1.5 * pi, const Offset(1, 0));
    addArc(1, 1.5 * pi, 2.0 * pi);
    addEdge(2, 0.0, const Offset(0, 1));
    addArc(2, 0.0, 0.5 * pi);
    addEdge(3, 0.5 * pi, const Offset(-1, 0));
    addArc(3, 0.5 * pi, pi);
    addEdge(0, pi, const Offset(0, -1));
    addArc(0, pi, 1.25 * pi);

    // The last pair coincides with the first one; fromPairs closes the loop.
    o.removeLast();
    i.removeLast();
    return ContourStrip.fromPairs(o, i);
  }

  /// Builds bands of half-width [halfWidth] centred on each contour of
  /// [path].
  ///
  /// Unlike [ContourStrip.rrectRing], the bands do not follow the exact
  /// outline of a stroke. They are meant to be at least as large as the stroke
  /// and then masked by it. To that end, the band is widened at corners to
  /// cover a mitered join, up to [miterLimit] times [halfWidth].
  ///
  /// Closed contours are made to run clockwise and to start at the point
  /// nearest the top-left corner of their bounds, so that shapes agree with
  /// [ContourStrip.rrectRing] on where the gradient starts. Open contours
  /// keep the direction of the path.
  ///
  /// Where the band would reach over another part of the contour, as on the
  /// narrow arms of a star, it is cut back to about halfway between the two,
  /// so that each point is colored by the part of the contour nearest to it.
  ///
  /// Contours are sampled every [step] logical pixels. Sharp corners between
  /// samples are found and added.
  static List<ContourStrip> alongPath(
    Path path, {
    required double halfWidth,
    double step = 2.0,
    double miterLimit = 4.0,
  }) {
    final List<_Polyline> lines = <_Polyline>[];
    for (final ui.PathMetric metric in path.computeMetrics()) {
      final List<Offset> points = _samplePolyline(metric, step);
      if (points.length < 2) {
        continue;
      }
      final bool closed = metric.isClosed && points.length > 2;
      if (closed) {
        _normalizeLoop(points);
      }
      lines.add(_Polyline(points, closed));
    }
    if (lines.isEmpty) {
      return const <ContourStrip>[];
    }
    final _SegmentGrid grid = _SegmentGrid(lines, halfWidth);
    // Bands overlap a little where they are cut, so that no pixel between
    // them is left uncovered. With the default step, this is about one
    // device pixel.
    final double overlap = step / 2;

    final List<ContourStrip> strips = <ContourStrip>[];
    for (int c = 0; c < lines.length; c++) {
      final List<Offset> points = lines[c].points;
      final bool closed = lines[c].closed;
      final List<Offset> o = <Offset>[];
      final List<Offset> i = <Offset>[];
      final List<Offset> centres = <Offset>[];
      int firstJoin = 0;
      final int n = points.length;
      for (int k = 0; k < n; k++) {
        final Offset p = points[k];
        final bool hasPrevious = closed || k > 0;
        final bool hasNext = closed || k < n - 1;
        final Offset a = hasPrevious
            ? _unit(p - points[(k - 1 + n) % n])
            : _unit(points[k + 1] - p);
        final Offset b = hasNext ? _unit(points[(k + 1) % n] - p) : a;
        final int start = o.length;
        _addJoin(o, i, p, a, b, halfWidth, miterLimit);
        for (int j = start; j < o.length; j++) {
          o[j] = grid.cut(p, o[j], c, k, overlap);
          i[j] = grid.cut(p, i[j], c, k, overlap);
          centres.add(p);
        }
        if (k == 0) {
          firstJoin = o.length;
        }
      }
      // If a loop starts at a sharp corner, start it halfway around the
      // corner's fan, so the gradient's seam runs through the tip of the
      // corner, as it does for rrectRing.
      if (closed && firstJoin > 1) {
        final int shift = firstJoin ~/ 2;
        _rotate(o, shift);
        _rotate(i, shift);
        _rotate(centres, shift);
      }
      strips.add(
        ContourStrip.fromPairs(o, i, centres: centres, closed: closed),
      );
    }
    return strips;
  }

  static void _rotate(List<Offset> list, int shift) {
    final List<Offset> rotated = <Offset>[
      ...list.skip(shift),
      ...list.take(shift),
    ];
    list
      ..clear()
      ..addAll(rotated);
  }

  /// Samples [metric] as a polyline, including sharp corners that fall
  /// between samples. Consecutive duplicate points are dropped.
  static List<Offset> _samplePolyline(ui.PathMetric metric, double step) {
    final double length = metric.length;
    if (!(length > 0)) {
      return const <Offset>[];
    }
    final int count = (length / step).ceil().clamp(3, 4096);
    final bool closed = metric.isClosed;
    final List<ui.Tangent> tangents = <ui.Tangent>[
      for (int k = 0; k <= count; k++)
        if (k < count || !closed)
          metric.getTangentForOffset(length * k / count)!,
    ];

    final List<Offset> points = <Offset>[];
    void add(Offset p) {
      if (points.isEmpty || (points.last - p).distanceSquared > 1e-12) {
        points.add(p);
      }
    }

    final int segments = closed ? tangents.length : tangents.length - 1;
    for (int k = 0; k < tangents.length; k++) {
      final ui.Tangent t1 = tangents[k];
      add(t1.position);
      if (k >= segments) {
        continue;
      }
      final ui.Tangent t2 = tangents[(k + 1) % tangents.length];
      final Offset? corner = _cornerBetween(t1, t2);
      if (corner != null) {
        add(corner);
      }
    }
    if (closed &&
        points.length > 1 &&
        (points.first - points.last).distanceSquared <= 1e-12) {
      points.removeLast();
    }
    return points;
  }

  /// Where the tangent lines at [t1] and [t2] meet, if the contour turns
  /// noticeably between them and they meet in between.
  static Offset? _cornerBetween(ui.Tangent t1, ui.Tangent t2) {
    final Offset d1 = _unit(t1.vector);
    final Offset d2 = _unit(t2.vector);
    final double cross = _cross(d1, d2);
    final double dot = d1.dx * d2.dx + d1.dy * d2.dy;
    if (math.atan2(cross.abs(), dot) < 5 * math.pi / 180) {
      return null;
    }
    final Offset q = t2.position - t1.position;
    final double a = _cross(q, d2) / cross;
    final double b = _cross(d1, q) / cross;
    final double limit = q.distance;
    if (a <= 0 || b <= 0 || a >= limit || b >= limit) {
      return null;
    }
    return t1.position + d1 * a;
  }

  /// Makes a closed polyline run clockwise and start at the point nearest the
  /// top-left corner of its bounds.
  static void _normalizeLoop(List<Offset> points) {
    double area = 0;
    double left = double.infinity;
    double top = double.infinity;
    for (int k = 0; k < points.length; k++) {
      final Offset p = points[k];
      area += _cross(p, points[(k + 1) % points.length]);
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
    }
    // With y pointing down, a positive area means clockwise on screen.
    final List<Offset> ordered = area < 0 ? points.reversed.toList() : points;
    final Offset topLeft = Offset(left, top);
    int start = 0;
    for (int k = 1; k < ordered.length; k++) {
      if ((ordered[k] - topLeft).distanceSquared <
          (ordered[start] - topLeft).distanceSquared) {
        start = k;
      }
    }
    if (!identical(ordered, points)) {
      points
        ..clear()
        ..addAll(ordered);
    }
    _rotate(points, start);
  }

  /// Adds the pairs for point [p], where the contour arrives in direction [a]
  /// and leaves in direction [b].
  ///
  /// Gentle turns get one pair along the bisector, stretched to keep the
  /// band's width. Sharp turns get a fan that is wide enough on the convex side
  /// to cover a mitered join. The fan has a single color, the one at [p].
  ///
  /// The fan only covers the convex side: on the concave side, the bands of
  /// the two neighbouring segments already overlap, and a fan there would
  /// paint the corner's color over them. Its first and last pairs are
  /// repeated at full width so that the neighbouring quads keep their shape,
  /// unless the turn is sharper than a right angle: then each neighbouring
  /// band's end would reach across the other segment, and alongPath has
  /// already cut the pairs before and after the corner back to the bisector.
  /// The fan has an even number of steps, so that its middle pair lies on the
  /// bisector.
  static void _addJoin(
    List<Offset> o,
    List<Offset> i,
    Offset p,
    Offset a,
    Offset b,
    double halfWidth,
    double miterLimit,
  ) {
    final double turn = math.atan2(_cross(a, b), a.dx * b.dx + a.dy * b.dy);
    final Offset na = _normalOf(a);
    if (turn.abs() < math.pi / 6) {
      final Offset bisector = _unit(na + _normalOf(b));
      final double length = halfWidth / math.cos(turn / 2);
      o.add(p + bisector * length);
      i.add(p - bisector * length);
      return;
    }
    final double convex = math.min(
      halfWidth / math.max(math.cos(turn / 2), 1e-6),
      halfWidth * miterLimit,
    );
    void addPair(Offset n, double concave) {
      // A positive turn is clockwise, which bends towards the inside, so the
      // outer side is the convex one.
      o.add(p + n * (turn > 0 ? convex : concave));
      i.add(p - n * (turn > 0 ? concave : convex));
    }

    final double ends = turn.abs() <= math.pi / 2 ? halfWidth : 0;
    final int steps = 2 * (turn.abs() / (2 * math.pi / 9)).ceil();
    for (int s = 0; s <= steps; s++) {
      final double angle = turn * s / steps;
      final double c = math.cos(angle);
      final double sn = math.sin(angle);
      final Offset n = Offset(na.dx * c - na.dy * sn, na.dx * sn + na.dy * c);
      if (s == 0) {
        addPair(n, ends);
      }
      addPair(n, 0);
      if (s == steps) {
        addPair(n, ends);
      }
    }
  }

  /// The outward normal of direction [d] on a clockwise contour.
  static Offset _normalOf(Offset d) => Offset(d.dy, -d.dx);

  static Offset _unit(Offset v) {
    final double length = v.distance;
    return length > 0 ? v / length : const Offset(1, 0);
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  /// Points on the outer edge. For a closed strip, the first point is
  /// repeated at the end.
  final List<Offset> outer;

  /// Points on the inner edge. For a closed strip, the first point is
  /// repeated at the end.
  final List<Offset> inner;

  /// Distance along the centre line from the first pair to each pair.
  final List<double> distances;

  /// Whether the strip runs back to where it started.
  final bool closed;

  /// Total length of the centre line.
  double get length => distances.last;
}

/// A contour sampled as a polyline.
class _Polyline {
  const _Polyline(this.points, this.closed);

  final List<Offset> points;
  final bool closed;

  /// Segment `j` runs from `points[j]` to the next point.
  int get segmentCount => closed ? points.length : points.length - 1;

  Offset segmentStart(int j) => points[j];
  Offset segmentEnd(int j) => points[(j + 1) % points.length];
}

/// The segments of some polylines, bucketed by position so that the ones
/// near a point can be found quickly.
class _SegmentGrid {
  _SegmentGrid(this._lines, double cellSize) {
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    for (final _Polyline line in _lines) {
      for (final Offset p in line.points) {
        left = math.min(left, p.dx);
        top = math.min(top, p.dy);
        right = math.max(right, p.dx);
        bottom = math.max(bottom, p.dy);
      }
    }
    _left = left;
    _top = top;
    // Large shapes get larger cells, to keep the grid small.
    _cellSize = math.max(
      math.max(cellSize, 1e-3),
      math.max(right - left, bottom - top) / 128,
    );
    _columns = ((right - left) / _cellSize).floor() + 1;
    _rows = ((bottom - top) / _cellSize).floor() + 1;
    _cells = List<List<int>?>.filled(_columns * _rows, null);
    for (int c = 0; c < _lines.length; c++) {
      final _Polyline line = _lines[c];
      for (int j = 0; j < line.segmentCount; j++) {
        _visitCells(
          Rect.fromPoints(line.segmentStart(j), line.segmentEnd(j)),
          (int index) => (_cells[index] ??= <int>[])
            ..add(c)
            ..add(j),
        );
      }
    }
  }

  final List<_Polyline> _lines;
  late final double _left;
  late final double _top;
  late final double _cellSize;
  late final int _columns;
  late final int _rows;

  /// For each cell, the line and segment index of each segment that may
  /// pass through it, one after the other.
  late final List<List<int>?> _cells;

  void _visitCells(Rect bounds, void Function(int index) visit) {
    int column(double x) =>
        ((x - _left) / _cellSize).floor().clamp(0, _columns - 1);
    int row(double y) => ((y - _top) / _cellSize).floor().clamp(0, _rows - 1);
    final int lastColumn = column(bounds.right);
    final int lastRow = row(bounds.bottom);
    for (int y = row(bounds.top); y <= lastRow; y++) {
      for (int x = column(bounds.left); x <= lastColumn; x++) {
        visit(y * _columns + x);
      }
    }
  }

  /// Moves [q] towards [p], point [k] of line [line], so that the band from
  /// [p] to [q] ends where it stops being nearer to [p] than to any other
  /// segment, plus [overlap].
  ///
  /// Going from [p] towards [q], a point at distance r from [p] belongs to
  /// [p] while no other segment is within r of it. That ends at the point
  /// the same distance from [p] and from the nearest other segment, which is
  /// halfway across a narrow part of the shape, or at the centre of a
  /// concave curve.
  ///
  /// Segments that end at [p] are ignored.
  Offset cut(Offset p, Offset q, int line, int k, double overlap) {
    final Offset d = q - p;
    final double length = d.distance;
    if (length == 0) {
      return q;
    }
    final double ux = d.dx / length;
    final double uy = d.dy / length;
    final _Polyline own = _lines[line];
    final int previous = own.closed ? (k - 1) % own.points.length : k - 1;
    double reach = length;

    // The distance along the ray at which the point is as far from (x, y)
    // as from p.
    void towardsPoint(double x, double y) {
      final double wx = x - p.dx;
      final double wy = y - p.dy;
      final double along = ux * wx + uy * wy;
      if (along > 0) {
        reach = math.min(reach, (wx * wx + wy * wy) / (2 * along));
      }
    }

    // Every point of the ray up to reach lies in the circle of radius reach
    // around p + u * reach, and so does every point within that distance of
    // it. Segments outside the circle can be skipped.
    _visitCells(Rect.fromCircle(center: q, radius: length), (int index) {
      final List<int>? cell = _cells[index];
      if (cell == null) {
        return;
      }
      for (int x = 0; x < cell.length; x += 2) {
        final int c = cell[x];
        final int j = cell[x + 1];
        if (c == line && (j == k || j == previous)) {
          continue;
        }
        final Offset a = _lines[c].segmentStart(j);
        final Offset b = _lines[c].segmentEnd(j);
        final double ex = b.dx - a.dx;
        final double ey = b.dy - a.dy;
        final double e2 = ex * ex + ey * ey;
        // The segment's point nearest the centre of the circle.
        final double cx = p.dx + ux * reach;
        final double cy = p.dy + uy * reach;
        final double f = e2 > 0
            ? (((cx - a.dx) * ex + (cy - a.dy) * ey) / e2).clamp(0.0, 1.0)
            : 0.0;
        final double nx = a.dx + ex * f - cx;
        final double ny = a.dy + ey * f - cy;
        if (nx * nx + ny * ny >= reach * reach) {
          continue;
        }
        if (e2 > 0) {
          // Nearest to the inside of the segment: the point's distance from
          // its line is h at p and changes by g for each unit along the ray.
          final double e = math.sqrt(e2);
          final double h = (ey * (a.dx - p.dx) - ex * (a.dy - p.dy)) / e;
          final double slope = (ex * uy - ey * ux) / e;
          final double g = h >= 0 ? slope : -slope;
          if (g < 1 - 1e-9) {
            final double r = h.abs() / (1 - g);
            final double mx = p.dx + ux * r - a.dx;
            final double my = p.dy + uy * r - a.dy;
            final double s = (mx * ex + my * ey) / e2;
            if (s >= 0 && s <= 1) {
              reach = math.min(reach, r);
            }
          }
        }
        // Nearest to one of its ends.
        towardsPoint(a.dx, a.dy);
        towardsPoint(b.dx, b.dy);
      }
    });
    reach += overlap;
    return reach < length ? p + d * (reach / length) : q;
  }
}

/// A corner of a rounded rectangle: an elliptical arc around [center].
class _Corner {
  const _Corner(this.center, this.rx, this.ry);

  /// The corners of [r] in the order top-left, top-right, bottom-right,
  /// bottom-left.
  static List<_Corner> of(RRect r) => <_Corner>[
    _Corner(
      Offset(r.left + r.tlRadiusX, r.top + r.tlRadiusY),
      r.tlRadiusX,
      r.tlRadiusY,
    ),
    _Corner(
      Offset(r.right - r.trRadiusX, r.top + r.trRadiusY),
      r.trRadiusX,
      r.trRadiusY,
    ),
    _Corner(
      Offset(r.right - r.brRadiusX, r.bottom - r.brRadiusY),
      r.brRadiusX,
      r.brRadiusY,
    ),
    _Corner(
      Offset(r.left + r.blRadiusX, r.bottom - r.blRadiusY),
      r.blRadiusX,
      r.blRadiusY,
    ),
  ];

  final Offset center;
  final double rx;
  final double ry;

  /// The point on the arc at [angle], measured clockwise from the positive x
  /// axis (y points down).
  Offset at(double angle) =>
      center + Offset(rx * math.cos(angle), ry * math.sin(angle));
}
