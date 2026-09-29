import 'dart:ui' show Color;

/// Returns [stops], or evenly spaced stops for [colorCount] colors when
/// [stops] is null.
List<double> resolveStops(int colorCount, List<double>? stops) {
  if (stops != null) {
    return stops;
  }
  if (colorCount == 1) {
    return const <double>[0.0];
  }
  return List<double>.generate(
    colorCount,
    (int i) => i / (colorCount - 1),
    growable: false,
  );
}

/// Makes the gradient described by [colors] and [stops] run around a loop,
/// ending where it starts.
///
/// If [stops] is null, the colors are spaced evenly around the loop, so each
/// takes up the same share of it, and the last blends back into the first.
/// Otherwise, the gap between the last stop and the first stop, going round
/// through 1.0, blends from the last color to the first.
({List<Color> colors, List<double> stops}) wrapColorStops(
  List<Color> colors,
  List<double>? stops,
) {
  if (stops == null) {
    final int count = colors.length;
    return (
      colors: <Color>[...colors, colors.first],
      stops: <double>[for (int i = 0; i <= count; i++) i / count],
    );
  }
  final double gap = 1.0 - stops.last + stops.first;
  if (gap <= 0) {
    return (colors: colors, stops: stops);
  }
  final Color atZero = Color.lerp(
    colors.last,
    colors.first,
    (1.0 - stops.last) / gap,
  )!;
  return (
    colors: <Color>[atZero, ...colors, atZero],
    stops: <double>[0.0, ...stops, 1.0],
  );
}

/// Returns the color of the gradient described by [colors] and [stops] at
/// position [t] in the range 0.0 to 1.0.
///
/// [segmentHint] picks the stop interval to interpolate in. It must lie in the
/// same interval as [t]; it is only needed to disambiguate a [t] that falls
/// exactly on a hard stop (two equal stops). When omitted, [t] itself is used.
Color colorAt(
  List<Color> colors,
  List<double> stops,
  double t, {
  double? segmentHint,
}) {
  final double hint = segmentHint ?? t;
  if (hint <= stops.first) {
    return colors.first;
  }
  if (hint >= stops.last) {
    return colors.last;
  }
  for (int i = 0; i < stops.length - 1; i++) {
    final double a = stops[i];
    final double b = stops[i + 1];
    if (hint >= a && hint <= b && b > a) {
      final double f = ((t - a) / (b - a)).clamp(0.0, 1.0);
      return Color.lerp(colors[i], colors[i + 1], f)!;
    }
  }
  return colors.last;
}

/// Linearly interpolates between two gradients that may have a different
/// number of colors, by sampling both at the union of their stops.
///
/// Hard stops (a color change at a single position) in either gradient are
/// preserved by emitting that position twice, once with the color on each
/// side of it.
({List<Color> colors, List<double> stops}) lerpColorStops(
  List<Color> aColors,
  List<double>? aStops,
  List<Color> bColors,
  List<double>? bStops,
  double t,
) {
  final List<double> resolvedA = resolveStops(aColors.length, aStops);
  final List<double> resolvedB = resolveStops(bColors.length, bStops);
  final List<double> union = <double>{...resolvedA, ...resolvedB}.toList()
    ..sort();

  Color sample(double s, double hint) => Color.lerp(
    colorAt(aColors, resolvedA, s, segmentHint: hint),
    colorAt(bColors, resolvedB, s, segmentHint: hint),
    t,
  )!;

  const double epsilon = 1e-9;
  final List<Color> colors = <Color>[];
  final List<double> stops = <double>[];
  for (final double s in union) {
    final Color before = sample(s, s - epsilon);
    final Color after = sample(s, s + epsilon);
    colors.add(before);
    stops.add(s);
    if (after != before) {
      colors.add(after);
      stops.add(s);
    }
  }
  return (colors: colors, stops: stops);
}
