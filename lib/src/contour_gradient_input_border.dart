import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'contour_gradient_border.dart';

/// An [InputBorder] for text fields, shaped like any [OutlinedBorder] and
/// painted with a gradient that runs along the border.
///
/// This is the [InputDecoration] counterpart of [ContourGradientBorder], and
/// takes the same [colors], [stops], [startOffset] and [shape]. Like
/// [OutlineInputBorder], it leaves a gap in the top of the border for a
/// floating label, [gapPadding] wide on either side of the label.
///
/// ```dart
/// const TextField(
///   decoration: InputDecoration(
///     labelText: 'Name',
///     border: ContourGradientInputBorder(
///       colors: [Colors.purple, Colors.orange],
///       shape: StadiumBorder(),
///     ),
///   ),
/// )
/// ```
///
/// The input decorator replaces [borderSide] with its own, based on the theme
/// and on whether the field has focus, so the width changes with focus. The
/// color of [borderSide] is ignored, which means an error does not change the
/// border's colors. Set [InputDecoration.errorBorder] and
/// [InputDecoration.focusedErrorBorder] to show errors.
class ContourGradientInputBorder extends InputBorder {
  /// Creates an input border shaped like [shape], painted with a gradient
  /// along its length.
  ///
  /// If [stops] is non-null, it must have the same length as [colors] and its
  /// values must be in the range 0.0 to 1.0, in ascending order.
  const ContourGradientInputBorder({
    required this.colors,
    this.stops,
    this.startOffset = 0.0,
    this.shape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4.0)),
    ),
    super.borderSide = const BorderSide(),
    this.gapPadding = 4.0,
  }) : assert(gapPadding >= 0.0);

  /// The colors the gradient takes along the border.
  ///
  /// See [ContourGradientBorder.colors].
  final List<Color> colors;

  /// Positions of [colors] along the border, as fractions of its length.
  ///
  /// See [ContourGradientBorder.stops].
  final List<double>? stops;

  /// How far the gradient is moved clockwise along the border, as a fraction
  /// of its length.
  ///
  /// See [ContourGradientBorder.startOffset].
  final double startOffset;

  /// The shape of the border.
  ///
  /// Its [OutlinedBorder.side] is replaced by [borderSide]. Defaults to a
  /// rounded rectangle with a radius of 4, like [OutlineInputBorder].
  final OutlinedBorder shape;

  /// Horizontal padding on either side of the gap for a floating label.
  final double gapPadding;

  ContourGradientBorder get _border => ContourGradientBorder(
    colors: colors,
    stops: stops,
    startOffset: startOffset,
    shape: shape,
    side: borderSide,
  );

  static ContourGradientInputBorder _fromBorder(
    ContourGradientBorder border,
    double gapPadding,
  ) {
    return ContourGradientInputBorder(
      colors: border.colors,
      stops: border.stops,
      startOffset: border.startOffset,
      shape: border.shape,
      borderSide: border.side,
      gapPadding: gapPadding,
    );
  }

  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.strokeInset);

  /// Returns a copy of this border with the given fields replaced with the
  /// new values.
  @override
  ContourGradientInputBorder copyWith({
    BorderSide? borderSide,
    List<Color>? colors,
    List<double>? stops,
    double? startOffset,
    OutlinedBorder? shape,
    double? gapPadding,
  }) {
    return ContourGradientInputBorder(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      startOffset: startOffset ?? this.startOffset,
      shape: shape ?? this.shape,
      borderSide: borderSide ?? this.borderSide,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }

  @override
  ContourGradientInputBorder scale(double t) {
    return _fromBorder(_border.scale(t), gapPadding * t);
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    final ContourGradientInputBorder? from = _asGradientInputBorder(a);
    if (from != null) {
      return _lerp(from, this, t);
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    final ContourGradientInputBorder? to = _asGradientInputBorder(b);
    if (to != null) {
      return _lerp(this, to, t);
    }
    return super.lerpTo(b, t);
  }

  /// Converts borders that this one knows how to animate from or to. An
  /// [OutlineInputBorder] becomes a gradient border of a single color, so a
  /// field can animate between the two, for example when it gains focus.
  static ContourGradientInputBorder? _asGradientInputBorder(
    ShapeBorder? border,
  ) {
    return switch (border) {
      final ContourGradientInputBorder b => b,
      final OutlineInputBorder b => ContourGradientInputBorder(
        colors: <Color>[b.borderSide.color],
        shape: RoundedRectangleBorder(borderRadius: b.borderRadius),
        borderSide: b.borderSide,
        gapPadding: b.gapPadding,
      ),
      _ => null,
    };
  }

  static ContourGradientInputBorder _lerp(
    ContourGradientInputBorder a,
    ContourGradientInputBorder b,
    double t,
  ) {
    return _fromBorder(
      ShapeBorder.lerp(a._border, b._border, t)! as ContourGradientBorder,
      ui.lerpDouble(a.gapPadding, b.gapPadding, t)!,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _border.getInnerPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _border.getOuterPath(rect, textDirection: textDirection);
  }

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    _border.paintInterior(canvas, rect, paint, textDirection: textDirection);
  }

  @override
  bool get preferPaintInterior => _border.preferPaintInterior;

  /// Paints the border around [rect].
  ///
  /// As with [OutlineInputBorder], the top of the border may be interrupted
  /// by a gap for a floating label if [gapExtent] is non-zero. The gap starts
  /// at `gapStart - gapPadding` (for [TextDirection.ltr]) and is
  /// `(gapPadding + gapExtent + gapPadding) * gapPercentage` wide.
  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    assert(gapPercentage >= 0.0 && gapPercentage <= 1.0);
    final ContourGradientBorder border = _border;
    if (gapStart == null || gapExtent <= 0.0 || gapPercentage == 0.0) {
      border.paint(canvas, rect, textDirection: textDirection);
      return;
    }
    final double extent = ui.lerpDouble(
      0.0,
      gapExtent + gapPadding * 2.0,
      gapPercentage,
    )!;
    final double start = math.max(0.0, switch (textDirection!) {
      TextDirection.rtl => gapStart + gapPadding - extent,
      TextDirection.ltr => gapStart - gapPadding,
    });
    // Everything around the border except the gap. The gap lies inside the
    // outer rectangle, so the even-odd rule makes it a hole.
    final Path clip = _gapPath(rect, start, start + extent, textDirection)
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(borderSide.width * 2 + 8.0));
    canvas
      ..save()
      ..clipPath(clip);
    border.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }

  /// The area cut out of the border for a label gap from [start] to [end].
  ///
  /// The gap cuts straight down through the top of the border. Where it
  /// reaches into a rounded top corner, it cuts along the corner's radius
  /// instead, where [OutlineInputBorder] ends the corner's arc. Like
  /// [OutlineInputBorder], [start] and [end] are measured from the left of
  /// [rect].
  Path _gapPath(
    Rect rect,
    double start,
    double end,
    TextDirection textDirection,
  ) {
    final double top = rect.top - borderSide.strokeOutset - 1.0;
    final RRect? centreLine = switch (shape) {
      final RoundedRectangleBorder s =>
        s.borderRadius.resolve(textDirection).toRRect(rect),
      StadiumBorder() => RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide / 2),
      ),
      _ => null,
    }?.inflate(borderSide.strokeOffset / 2).scaleRadii();

    if (centreLine == null) {
      // Other shapes have no top corners to follow; cut through their top
      // half, which is where their outline crosses the top edge.
      return Path()..addRect(
        Rect.fromLTRB(
          rect.left + start,
          top,
          rect.left + end,
          rect.top + rect.height / 2,
        ),
      );
    }

    final double bottom = rect.top + borderSide.strokeInset + 1.0;
    Offset leftInner = Offset(rect.left + start, bottom);
    Offset leftOuter = Offset(rect.left + start, top);
    Offset rightInner = Offset(rect.left + end, bottom);
    Offset rightOuter = Offset(rect.left + end, top);

    final double tl = centreLine.tlRadiusX;
    if (tl > 0 && start <= tl) {
      final Offset centre = Offset(
        centreLine.left + tl,
        centreLine.top + centreLine.tlRadiusY,
      );
      final double sweep = math.acos(clampDouble(1 - start / tl, 0.0, 1.0));
      leftInner = centre;
      leftOuter =
          centre +
          Offset(-math.cos(sweep), -math.sin(sweep)) *
              (tl + borderSide.width + 2.0);
    }

    final double tr = centreLine.trRadiusX;
    final double fromRight = rect.width - end;
    if (tr > 0 && fromRight < tr) {
      final Offset centre = Offset(
        centreLine.right - tr,
        centreLine.top + centreLine.trRadiusY,
      );
      final double sweep = math.asin(clampDouble(1 - fromRight / tr, 0.0, 1.0));
      rightInner = centre;
      rightOuter =
          centre +
          Offset(math.sin(sweep), -math.cos(sweep)) *
              (tr + borderSide.width + 2.0);
    }

    return Path()..addPolygon(<Offset>[
      leftInner,
      leftOuter,
      Offset(leftOuter.dx, top),
      Offset(rightOuter.dx, top),
      rightOuter,
      rightInner,
    ], true);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ContourGradientInputBorder &&
        other.borderSide == borderSide &&
        other.shape == shape &&
        other.startOffset == startOffset &&
        other.gapPadding == gapPadding &&
        listEquals(other.colors, colors) &&
        listEquals(other.stops, stops);
  }

  @override
  int get hashCode => Object.hash(
    borderSide,
    shape,
    startOffset,
    gapPadding,
    Object.hashAll(colors),
    stops == null ? null : Object.hashAll(stops!),
  );

  @override
  String toString() {
    return '${objectRuntimeType(this, 'ContourGradientInputBorder')}'
        '($borderSide, $shape, colors: $colors, stops: $stops, '
        'startOffset: $startOffset, gapPadding: $gapPadding)';
  }
}
