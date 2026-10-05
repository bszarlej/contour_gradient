// A stress test for animated gradient borders.
//
// Run it in profile mode on a real device; debug mode numbers are
// meaningless:
//
//     flutter run --profile -t lib/benchmark.dart
//
// For automated runs that write frame timings to build/benchmark, see
// integration_test/benchmark_test.dart.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:contour_gradient/contour_gradient.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const BenchmarkApp());
}

const List<Color> _colors = <Color>[
  Color(0xFF7F00FF),
  Color(0xFF00C6FF),
  Color(0xFFFF4E50),
  Color(0xFF7F00FF),
];

/// The shapes the benchmark can fill the screen with.
enum BenchmarkShape {
  roundedRectangle(
    'Rounded rectangle',
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
  ),
  stadium('Stadium', StadiumBorder()),
  beveled(
    'Beveled',
    BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  ),
  superellipse(
    'Superellipse',
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  oval('Oval', OvalBorder()),
  star('Star', StarBorder(innerRadiusRatio: 0.45));

  const BenchmarkShape(this.label, this.shape);

  final String label;
  final OutlinedBorder shape;
}

/// The number of borders the controls offer.
const List<int> benchmarkCounts = <int>[24, 96, 240];

class BenchmarkApp extends StatelessWidget {
  const BenchmarkApp({
    super.key,
    this.shapes,
    this.count = 96,
    this.showControls = true,
  });

  /// The shapes to cycle through, or all of them if null.
  final List<BenchmarkShape>? shapes;
  final int count;
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contour Gradient Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: BenchmarkPage(
        shapes: shapes,
        count: count,
        showControls: showControls,
      ),
    );
  }
}

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({
    super.key,
    this.shapes,
    required this.count,
    required this.showControls,
  });

  final List<BenchmarkShape>? shapes;
  final int count;
  final bool showControls;

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  late List<BenchmarkShape>? _shapes = widget.shapes;
  late int _count = widget.count;
  bool _animate = true;

  final _FrameStats _stats = _FrameStats();

  String get _scenario =>
      '${_shapes?.map((BenchmarkShape s) => s.name).join('+') ?? 'mixed'}'
      ' x$_count${_animate ? '' : ' (still)'}';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_stats.add);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_stats.add);
    _stats.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    setState(change);
    _stats.reset();
  }

  @override
  Widget build(BuildContext context) {
    final Widget grid = Padding(
      padding: const EdgeInsets.all(8),
      child: BorderGrid(
        shapes: _shapes ?? BenchmarkShape.values,
        count: _count,
        animate: _animate,
      ),
    );
    if (!widget.showControls) {
      return Scaffold(body: SafeArea(child: grid));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Controls(
              shapes: _shapes,
              count: _count,
              animate: _animate,
              onShapes: (List<BenchmarkShape>? s) => _update(() => _shapes = s),
              onCount: (int c) => _update(() => _count = c),
              onAnimate: (bool a) => _update(() => _animate = a),
              onMeasurePaint: () => _showPaintCost(context),
            ),
            RepaintBoundary(
              child: _StatsBar(
                stats: _stats,
                onLog: () => debugPrint('[$_scenario] ${_stats.summary()}'),
              ),
            ),
            Expanded(child: grid),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaintCost(BuildContext context) async {
    // Let the dialog's spinner show before the measurement blocks the UI.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final Map<BenchmarkShape, double> costs = measurePaintCost();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    final String report = <String>[
      'paint() cost, µs per border:',
      for (final MapEntry<BenchmarkShape, double> e in costs.entries)
        '  ${e.key.label.padRight(18)}${e.value.toStringAsFixed(1).padLeft(8)}',
    ].join('\n');
    debugPrint(report);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('paint() cost'),
        content: Text(
          report,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}

/// The key under which integration_test/benchmark_test.dart reports the
/// result of [measurePaintCost].
const String paintCostKey = 'paint_cost';

/// Times [ContourGradientBorder.paint] for each shape, recording into a
/// picture as a frame would, with a different start offset on every call as
/// in an animation. Returns microseconds per call.
///
/// [scale] scales the canvas. In a frame, the canvas a border paints on is
/// usually not scaled, because the device pixel ratio is applied by the root
/// layer, so the default of 1 matches what happens in an app.
///
/// This measures the CPU cost of painting a border, not of rasterizing it.
Map<BenchmarkShape, double> measurePaintCost({
  double scale = 1.0,
  Size size = const Size(120, 80),
  Duration budget = const Duration(milliseconds: 500),
}) {
  return <BenchmarkShape, double>{
    for (final BenchmarkShape shape in BenchmarkShape.values)
      shape: () {
        final ContourGradientBorder border = shape.shape
            .copyWith(side: const BorderSide(width: 3))
            .withGradient(_colors);
        final Rect rect = Offset.zero & size;
        ui.PictureRecorder recorder = ui.PictureRecorder();
        Canvas canvas = Canvas(recorder)..scale(scale);
        void paint(int i) {
          // Start a new recording now and then, so it does not grow forever.
          if (i % 64 == 0) {
            recorder.endRecording().dispose();
            recorder = ui.PictureRecorder();
            canvas = Canvas(recorder)..scale(scale);
          }
          border.copyWith(startOffset: i / 97).paint(canvas, rect);
        }

        for (int i = 1; i < 50; i++) {
          paint(i);
        }
        final Stopwatch watch = Stopwatch()..start();
        int runs = 0;
        while (watch.elapsed < budget) {
          paint(runs++);
        }
        recorder.endRecording().dispose();
        return watch.elapsedMicroseconds / runs;
      }(),
  };
}

/// [count] borders of [shapes], sized to fit the available space, whose
/// gradient goes round once every three seconds while [animate] is true.
///
/// The animation rebuilds the borders with a new start offset on every
/// frame, which is how the package is meant to be animated.
class BorderGrid extends StatefulWidget {
  const BorderGrid({
    super.key,
    required this.shapes,
    required this.count,
    this.animate = true,
  });

  final List<BenchmarkShape> shapes;
  final int count;
  final bool animate;

  @override
  State<BorderGrid> createState() => _BorderGridState();
}

class _BorderGridState extends State<BorderGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  static const double _spacing = 4;
  static const double _aspectRatio = 1.5;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BorderGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The largest tile size at which [count] tiles fit in [space].
  static Size _tileSize(int count, Size space) {
    for (int columns = 1; columns <= count; columns++) {
      final double width = (space.width - (columns - 1) * _spacing) / columns;
      final double height = width / _aspectRatio;
      final int rows = (count / columns).ceil();
      if (rows * height + (rows - 1) * _spacing <= space.height) {
        return Size(width, height);
      }
    }
    final double side = math.max(1, space.shortestSide / count);
    return Size(side * _aspectRatio, side);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size tile = _tileSize(widget.count, constraints.biggest);
        return AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double offset = _controller.value;
            return Wrap(
              spacing: _spacing,
              runSpacing: _spacing,
              children: <Widget>[
                for (int i = 0; i < widget.count; i++)
                  SizedBox.fromSize(
                    size: tile,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: widget.shapes[i % widget.shapes.length].shape
                            .copyWith(side: const BorderSide(width: 3))
                            .withGradient(_colors, startOffset: offset),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.shapes,
    required this.count,
    required this.animate,
    required this.onShapes,
    required this.onCount,
    required this.onAnimate,
    required this.onMeasurePaint,
  });

  final List<BenchmarkShape>? shapes;
  final int count;
  final bool animate;
  final ValueChanged<List<BenchmarkShape>?> onShapes;
  final ValueChanged<int> onCount;
  final ValueChanged<bool> onAnimate;
  final VoidCallback onMeasurePaint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          DropdownButton<BenchmarkShape?>(
            value: shapes?.single,
            items: <DropdownMenuItem<BenchmarkShape?>>[
              const DropdownMenuItem<BenchmarkShape?>(child: Text('Mixed')),
              for (final BenchmarkShape s in BenchmarkShape.values)
                DropdownMenuItem<BenchmarkShape?>(
                  value: s,
                  child: Text(s.label),
                ),
            ],
            onChanged: (BenchmarkShape? s) =>
                onShapes(s == null ? null : <BenchmarkShape>[s]),
          ),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (final int c in benchmarkCounts)
                ButtonSegment<int>(value: c, label: Text('$c')),
            ],
            selected: <int>{count},
            onSelectionChanged: (Set<int> s) => onCount(s.single),
            showSelectedIcon: false,
          ),
          FilterChip(
            label: const Text('Animate'),
            selected: animate,
            onSelected: onAnimate,
          ),
          TextButton(
            onPressed: onMeasurePaint,
            child: const Text('paint() cost'),
          ),
        ],
      ),
    );
  }
}

/// Build and raster times of recent frames.
class _FrameStats extends ChangeNotifier {
  static const int _window = 240;

  final List<FrameTiming> _frames = <FrameTiming>[];

  void add(List<FrameTiming> timings) {
    _frames.addAll(timings);
    if (_frames.length > _window) {
      _frames.removeRange(0, _frames.length - _window);
    }
    notifyListeners();
  }

  void reset() {
    _frames.clear();
    notifyListeners();
  }

  String summary() {
    if (_frames.isEmpty) {
      return 'waiting for frames…';
    }
    final double budget =
        1000 /
        WidgetsBinding
            .instance
            .platformDispatcher
            .views
            .first
            .display
            .refreshRate;
    String describe(List<double> ms) {
      final List<double> sorted = ms.toList()..sort();
      double at(double p) =>
          sorted[((sorted.length - 1) * p).round().clamp(0, sorted.length - 1)];
      final double mean =
          sorted.reduce((double a, double b) => a + b) / sorted.length;
      final int missed = sorted.where((double t) => t > budget).length;
      return 'avg ${mean.toStringAsFixed(1)} '
          'p90 ${at(0.9).toStringAsFixed(1)} '
          'p99 ${at(0.99).toStringAsFixed(1)} '
          'missed $missed';
    }

    double ms(Duration d) => d.inMicroseconds / 1000;
    return '${_frames.length} frames, budget ${budget.toStringAsFixed(1)} ms\n'
        'build  ${describe(<double>[for (final FrameTiming f in _frames) ms(f.buildDuration)])}\n'
        'raster ${describe(<double>[for (final FrameTiming f in _frames) ms(f.rasterDuration)])}';
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.onLog});

  final _FrameStats stats;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stats,
      builder: (BuildContext context, Widget? child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                stats.summary(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            IconButton(
              tooltip: 'Log to console',
              onPressed: onLog,
              icon: const Icon(Icons.terminal),
            ),
          ],
        ),
      ),
    );
  }
}
