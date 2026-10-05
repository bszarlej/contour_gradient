// Records frame timings while animated gradient borders fill the screen, for
// each scenario below.
//
// Run in profile mode on a real device:
//
//     flutter drive --profile --no-dds \
//       --driver=test_driver/perf_driver.dart \
//       --target=integration_test/benchmark_test.dart
//
// The driver prints a summary and writes each scenario's timings to
// build/benchmark/<scenario>.json.

import 'package:contour_gradient_example/benchmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The shapes of each scenario: rounded rectangles are painted directly,
/// stars along their path, and mixed alternates all shapes.
const Map<String, List<BenchmarkShape>?> _scenarios =
    <String, List<BenchmarkShape>?>{
      'rrect': <BenchmarkShape>[BenchmarkShape.roundedRectangle],
      'star': <BenchmarkShape>[BenchmarkShape.star],
      'mixed': null,
    };

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the animation drive frames as it would in an app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // First, while the device is still cool.
  testWidgets('paint() cost', (WidgetTester tester) async {
    binding.reportData ??= <String, dynamic>{};
    binding.reportData![paintCostKey] = <String, dynamic>{
      for (final MapEntry<BenchmarkShape, double> e
          in measurePaintCost().entries)
        e.key.name: e.value,
    };
  });

  for (final MapEntry<String, List<BenchmarkShape>?> scenario
      in _scenarios.entries) {
    for (final int count in benchmarkCounts) {
      final String name = '${scenario.key}_$count';
      testWidgets(name, (WidgetTester tester) async {
        await tester.pumpWidget(
          BenchmarkApp(
            shapes: scenario.value,
            count: count,
            showControls: false,
          ),
        );
        // Skip the first frames, which compile shaders.
        await Future<void>.delayed(const Duration(seconds: 1));
        await binding.watchPerformance(() async {
          await Future<void>.delayed(const Duration(seconds: 5));
        }, reportKey: name);
      });
    }
  }
}
