import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where the shader is bundled: under the package's name when it is a
/// dependency, and without it when it is the app itself, as in its tests.
const List<String> _shaderKeys = <String>[
  'packages/contour_gradient/shaders/contour_gradient.frag',
  'shaders/contour_gradient.frag',
];

ui.FragmentShader? _shader;
Future<void>? _loading;

/// The shader that colors a border from its `ContourMap`, or null until it is
/// loaded.
///
/// The first call starts loading it. If it cannot be loaded, it stays null,
/// and borders are painted without it.
///
/// There is a single shader, set up anew for each border: a draw keeps its
/// own copy of the shader's uniforms and images.
ui.FragmentShader? contourShader() {
  if (debugDisableContourShader) {
    return null;
  }
  _loading ??= _load();
  return _shader;
}

Future<void> _load() async {
  Object? error;
  StackTrace? stack;
  for (final String key in _shaderKeys) {
    try {
      _shader = (await ui.FragmentProgram.fromAsset(key)).fragmentShader();
      return;
    } catch (e, s) {
      error = e;
      stack = s;
    }
  }
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error!,
      stack: stack,
      library: 'contour_gradient',
      context: ErrorDescription(
        'while loading the shader for borders that stroke their outline; '
        'they are painted in layers instead',
      ),
      silent: true,
    ),
  );
}

/// Completes once the shader is loaded, or has failed to load.
@visibleForTesting
Future<void> loadContourShader() {
  contourShader();
  return _loading ?? Future<void>.value();
}

/// Whether to paint every border without the shader, as before it loads.
@visibleForTesting
bool debugDisableContourShader = false;

/// A canvas that draws shapes with [shader] in place of their paint's color,
/// and passes everything else on to [canvas].
///
/// It lets a shape paint its own border, as only the shape knows exactly
/// where its border goes, with a gradient. It supports what Flutter's own
/// shapes draw their borders with.
class ShadingCanvas implements Canvas {
  /// Creates a canvas that draws on [canvas] with [shader].
  ShadingCanvas(this.canvas, this.shader);

  /// The canvas drawn on.
  final Canvas canvas;

  /// The shader every shape is drawn with.
  final Shader shader;

  Paint _shaded(Paint paint) => paint
    ..color = const Color(0xFF000000)
    ..shader = shader;

  @override
  void drawPath(Path path, Paint paint) =>
      canvas.drawPath(path, _shaded(paint));

  @override
  void drawRect(Rect rect, Paint paint) =>
      canvas.drawRect(rect, _shaded(paint));

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      canvas.drawRRect(rrect, _shaded(paint));

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) =>
      canvas.drawDRRect(outer, inner, _shaded(paint));

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, Paint paint) =>
      canvas.drawRSuperellipse(rsuperellipse, _shaded(paint));

  @override
  void drawOval(Rect rect, Paint paint) =>
      canvas.drawOval(rect, _shaded(paint));

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      canvas.drawCircle(c, radius, _shaded(paint));

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => canvas.drawArc(rect, startAngle, sweepAngle, useCenter, _shaded(paint));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      canvas.drawLine(p1, p2, _shaded(paint));

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
  void rotate(double radians) => canvas.rotate(radians);

  @override
  void transform(Float64List matrix4) => canvas.transform(matrix4);

  @override
  Float64List getTransform() => canvas.getTransform();

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => canvas.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      canvas.clipRRect(rrect, doAntiAlias: doAntiAlias);

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      canvas.clipPath(path, doAntiAlias: doAntiAlias);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'ShadingCanvas does not support ${invocation.memberName}.',
  );
}
