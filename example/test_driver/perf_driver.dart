// Collects the frame timings recorded by integration_test/benchmark_test.dart,
// writes them to build/benchmark and prints a summary.

// ignore_for_file: avoid_print

import 'package:integration_test/integration_test_driver.dart';

const List<(String, String)> _columns = <(String, String)>[
  ('frames', 'frame_count'),
  ('build avg', 'average_frame_build_time_millis'),
  ('p90', '90th_percentile_frame_build_time_millis'),
  ('p99', '99th_percentile_frame_build_time_millis'),
  ('missed', 'missed_frame_build_budget_count'),
  ('raster avg', 'average_frame_rasterizer_time_millis'),
  ('p90', '90th_percentile_frame_rasterizer_time_millis'),
  ('p99', '99th_percentile_frame_rasterizer_time_millis'),
  ('missed', 'missed_frame_rasterizer_budget_count'),
];

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      if (data == null) {
        return;
      }
      final StringBuffer table = StringBuffer()
        ..writeln('Frame timings in ms:')
        ..write('scenario'.padRight(12));
      for (final (String label, _) in _columns) {
        table.write(label.padLeft(11));
      }
      table.writeln();
      for (final MapEntry<String, dynamic> entry in data.entries) {
        final Map<String, dynamic> summary =
            entry.value as Map<String, dynamic>;
        await writeResponseData(
          summary,
          testOutputFilename: entry.key,
          destinationDirectory: 'build/benchmark',
        );
        // The paint() cost per shape; this key matches paintCostKey in
        // lib/benchmark.dart, which the driver cannot import.
        if (entry.key == 'paint_cost') {
          print('paint() cost in µs per border:');
          for (final MapEntry<String, dynamic> shape in summary.entries) {
            final double us = (shape.value as num).toDouble();
            print('  ${shape.key.padRight(18)}${us.toStringAsFixed(1)}');
          }
          continue;
        }
        table.write(entry.key.padRight(12));
        for (final (_, String key) in _columns) {
          final num value = summary[key] as num;
          table.write(
            (value is int ? '$value' : value.toStringAsFixed(2)).padLeft(11),
          );
        }
        table.writeln();
      }
      print(table);
    },
  );
}
