import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'contour_map.dart';
import 'contour_strip.dart';

/// Triangles covering some [ContourStrip]s, to be painted with a gradient
/// that runs along them.
///
/// The x texture coordinate of each vertex is its distance along the strips,
/// taken one after the other, so a shader whose colors change along the x
/// axis colors the band along its length. A shader that repeats every
/// [length] runs once along the band. The y texture coordinate is 0 on the
/// outer edge and 1 on the inner edge.
///
/// The band does not depend on the gradient, so it can be built once and
/// painted with any colors and start offset; see [shader].
class ContourBand {
  ContourBand._(
    this._positions,
    this._coordinates,
    this.bounds,
    this.length,
    this.area,
  ) : vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        _positions,
        textureCoordinates: _coordinates,
      );

  /// Builds the band covering [strips], with the given [area]. Returns null if
  /// the strips have no length.
  ///
  /// If [repeatEach] is true, the x texture coordinates are instead spaced
  /// so that a shader that repeats every [length] runs once along each strip.
  static ContourBand? fromStrips(
    List<ContourStrip> strips, {
    Path? area,
    bool repeatEach = false,
  }) {
    int quads = 0;
    double length = 0;
    for (final ContourStrip strip in strips) {
      quads += strip.outer.length - 1;
      length += strip.length;
    }
    if (quads <= 0 || !(length > 0) || !length.isFinite) {
      return null;
    }

    // Each quad is two triangles of three vertices of two coordinates.
    final Float32List positions = Float32List(quads * 12);
    final Float32List coordinates = Float32List(quads * 12);
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    int index = 0;

    void add(Offset p, double u, double v) {
      positions[index] = p.dx;
      positions[index + 1] = p.dy;
      coordinates[index] = u;
      coordinates[index + 1] = v;
      index += 2;
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }

    double travelled = 0;
    for (int s = 0; s < strips.length; s++) {
      final ContourStrip strip = strips[s];
      final List<Offset> outer = strip.outer;
      final List<Offset> inner = strip.inner;
      // Where each pair is along the band.
      double along(int k) => repeatEach
          ? (s + (strip.length > 0 ? strip.distances[k] / strip.length : 0)) *
                length
          : travelled + strip.distances[k];
      for (int k = 0; k < outer.length - 1; k++) {
        final double ua = along(k);
        final double ub = along(k + 1);
        add(outer[k], ua, 0);
        add(inner[k], ua, 1);
        add(inner[k + 1], ub, 1);
        add(outer[k], ua, 0);
        add(inner[k + 1], ub, 1);
        add(outer[k + 1], ub, 0);
      }
      travelled += strip.length;
    }

    return ContourBand._(
      positions,
      coordinates,
      Rect.fromLTRB(left, top, right, bottom),
      length,
      area,
    );
  }

  final Float32List _positions;
  final Float32List _coordinates;

  /// The triangles of the band, with texture coordinates as described in
  /// [ContourBand].
  final ui.Vertices vertices;

  /// The smallest rectangle containing the band.
  final Rect bounds;

  /// The total length of the strips the band covers.
  final double length;

  /// The area of the border the band is painted on, if it can be clipped to
  /// it.
  final Path? area;

  /// A shader that colors the band with the gradient described by [colors]
  /// and [stops], running along it once and moved along it by [startOffset],
  /// as a fraction of its length.
  ///
  /// The gradient repeats, so where its end meets its start the colors change
  /// in a hard edge.
  ///
  /// The shader samples an image of the gradient rather than computing it:
  /// Impeller draws vertices with texture coordinates directly only when
  /// their shader is an image, and otherwise first renders the shader into a
  /// new texture on every draw.
  Shader shader(List<Color> colors, List<double> stops, double startOffset) {
    final ui.Image image = gradientImage(colors, stops);
    // Keep the shader's coordinates small, however large the offset.
    final double shift = (startOffset - startOffset.floorToDouble()) * length;
    // Maps the image, one period of the gradient, onto the band's length,
    // starting [shift] along it, so that the gradient moves forwards along
    // the band, clockwise, as [startOffset] grows.
    final Float64List matrix = Float64List(16)
      ..[0] = length / gradientImageWidth
      ..[5] = 1
      ..[10] = 1
      ..[12] = shift
      ..[15] = 1;
    return ImageShader(
      image,
      TileMode.repeated,
      TileMode.clamp,
      matrix,
      filterQuality: FilterQuality.low,
    );
  }

  /// The band's [ContourMap] at [scale] pixels per logical pixel, or null
  /// while it is being built, or if it would be too large.
  ///
  /// The map is only built on the second call, as a band painted only once,
  /// as in an animation of its size, would not get to use it. Every call
  /// must pass the same [scale].
  ContourMap? map(double scale) {
    if (!_mapBuilt) {
      if (!_mapWanted) {
        _mapWanted = true;
        return null;
      }
      _mapBuilt = true;
      _map = ContourMap.build(
        positions: _positions,
        coordinates: _coordinates,
        bounds: bounds,
        length: length,
        scale: scale,
      );
    }
    assert(_map == null || _map!.scale == scale);
    return _map?.image == null ? null : _map;
  }

  ContourMap? _map;
  bool _mapWanted = false;
  bool _mapBuilt = false;

  /// Releases the band's vertices and map.
  void dispose() {
    vertices.dispose();
    _map?.dispose();
  }
}

/// An image of one period of the gradient described by [colors] and
/// [stops], [gradientImageWidth] pixels wide and one pixel high.
ui.Image gradientImage(List<Color> colors, List<double> stops) {
  return gradientImageCache.get(
    _GradientKey(colors, stops),
    () => _gradientImage(colors, stops),
  );
}

/// The width of the images of gradients, in pixels.
///
/// A hard stop is blurred over a pixel of the image, which is less than a
/// logical pixel on borders up to this long.
///
/// shaders/contour_gradient.frag assumes this width.
const int gradientImageWidth = 4096;

/// An image of the gradient described by [colors] and [stops], one pixel
/// high.
ui.Image _gradientImage(List<Color> colors, List<double> stops) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  const Rect rect = Rect.fromLTWH(0, 0, gradientImageWidth * 1.0, 1);
  Canvas(recorder).drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.topRight, colors, stops),
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(gradientImageWidth, 1);
  picture.dispose();
  return image;
}

/// The colors and stops of a gradient, compared by value.
@immutable
class _GradientKey {
  _GradientKey(List<Color> colors, List<double> stops)
    : colors = List<Color>.unmodifiable(colors),
      stops = List<double>.unmodifiable(stops);

  final List<Color> colors;
  final List<double> stops;

  @override
  bool operator ==(Object other) =>
      other is _GradientKey &&
      listEquals(other.colors, colors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(colors), Object.hashAll(stops));
}

/// A cache that holds at most [capacity] values, and discards the least
/// recently used one when it is full.
class LruCache<K extends Object, V> {
  /// Creates a cache that holds at most [capacity] values, and calls
  /// [onDiscard] with each value it discards.
  LruCache(this.capacity, this.onDiscard) : assert(capacity > 0);

  /// The most values the cache holds.
  final int capacity;

  /// Called with each value the cache discards, to release it.
  final void Function(V value) onDiscard;

  // Iterates in insertion order, which is kept as the order of use.
  final Map<K, V> _values = <K, V>{};

  /// The number of values in the cache.
  int get length => _values.length;

  /// Returns the value stored under [key], building and storing it with
  /// [build] if there is none.
  V get(K key, V Function() build) {
    if (_values.containsKey(key)) {
      final V value = _values.remove(key) as V;
      _values[key] = value;
      return value;
    }
    final V value = build();
    _values[key] = value;
    if (_values.length > capacity) {
      final K oldest = _values.keys.first;
      onDiscard(_values.remove(oldest) as V);
    }
    return value;
  }

  /// Removes and releases every value.
  void clear() {
    _values.values.forEach(onDiscard);
    _values.clear();
  }
}

// A picture that has drawn a band or an image keeps its own reference to it,
// so the caches can release them while such a picture is still in use.

/// The bands of the borders painted by this package, so that painting a
/// border again with other colors or another start offset, as in an
/// animation, does not rebuild its band.
final LruCache<Object, ContourBand?> contourBandCache =
    LruCache<Object, ContourBand?>(256, (ContourBand? band) => band?.dispose());

/// The images of the gradients the bands are painted with.
final LruCache<Object, ui.Image> gradientImageCache =
    LruCache<Object, ui.Image>(32, (ui.Image image) => image.dispose());
