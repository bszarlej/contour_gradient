# Benchmarks

There are three ways to measure how much painting gradient borders costs. Use
them to compare a change against the baseline below.

## Paint stages (quick, any machine)

```sh
flutter test benchmark
```

This times the stages of `ContourGradientBorder.paint` for each shape:
building the geometry, building the vertices, and the whole `paint()` call
recorded into a picture. It runs in debug mode, so only compare its numbers
with each other.

## Frame timings on a device (automated)

```sh
cd example
flutter drive --profile --no-dds \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/benchmark_test.dart
```

This fills the screen with 24, 96 and 240 animated borders of rounded
rectangles, stars, and a mix of all shapes, and records build and raster
times for 5 seconds each. It prints a summary and writes every scenario's
timings to `example/build/benchmark/<scenario>.json`. Run it on a real
device: emulators and debug mode give meaningless numbers.

## Interactive stress test

```sh
cd example
flutter run --profile -t lib/benchmark.dart
```

This shows the same grid with controls for the shape, the number of borders
and the animation, and live build and raster times. The terminal button logs
the current numbers. The **paint() cost** button times `paint()` for each
shape in AOT code at the device's pixel ratio.

## Baseline (1.1.0)

Samsung Galaxy S24 (SM-S921B, 120 Hz, Android 16), Flutter 3.47.5, profile
mode, default renderer. The frame budget is 8.3 ms. The phone throttles when
it gets warm, which can make a run up to 50% slower, so let it cool down
between runs and compare runs made in the same conditions.

`paint()` cost, µs per border, recorded unscaled as in a frame:

| Rounded rectangle | Stadium | Beveled | Superellipse | Oval | Star |
| ----------------: | ------: | ------: | -----------: | ---: | ---: |
|                44 |      58 |     459 |          504 |  347 |  477 |

Frame timings, ms:

| Scenario  | Frames | Build avg | Build p99 | Raster avg | Raster p99 |
| --------- | -----: | --------: | --------: | ---------: | ---------: |
| rrect_24  |    600 |       3.2 |       5.4 |        4.7 |        6.9 |
| rrect_96  |    311 |       9.8 |      13.4 |       10.7 |       14.0 |
| rrect_240 |    295 |      13.1 |      17.1 |       13.8 |       19.0 |
| star_24   |    301 |      11.9 |      13.9 |        8.8 |       11.4 |
| star_96   |    148 |      30.3 |      37.1 |       18.3 |       20.8 |
| star_240  |     66 |      69.8 |      80.9 |       33.6 |       39.7 |
| mixed_24  |    299 |      11.9 |      14.4 |        4.4 |        8.4 |
| mixed_96  |    200 |      20.0 |      23.0 |       15.6 |       17.1 |
| mixed_240 |    104 |      42.5 |      53.0 |       24.9 |       35.8 |

## Cached geometry, GPU gradient (unreleased)

Same device and conditions as the baseline. Borders now also sample their
outline at the device pixel ratio, which 1.1.0 missed.

`paint()` cost, µs per border:

| Rounded rectangle | Stadium | Beveled | Superellipse | Oval | Star |
| ----------------: | ------: | ------: | -----------: | ---: | ---: |
|                 9 |       7 |      13 |           13 |   10 |   14 |

Frame timings, ms:

| Scenario  | Frames | Build avg | Build p99 | Raster avg | Raster p99 |
| --------- | -----: | --------: | --------: | ---------: | ---------: |
| rrect_24  |    598 |       1.0 |       1.5 |        4.8 |        7.4 |
| rrect_96  |    574 |       4.0 |       8.5 |        6.2 |       12.4 |
| rrect_240 |    308 |       8.7 |      16.0 |       11.9 |       13.1 |
| star_24   |    611 |       1.1 |       1.3 |        5.8 |        6.6 |
| star_96   |    518 |       4.3 |      10.1 |        9.0 |       10.6 |
| star_240  |    219 |       8.4 |      11.8 |       22.3 |       25.1 |
| mixed_24  |    598 |       1.1 |       1.4 |        5.7 |        6.7 |
| mixed_96  |    423 |       5.7 |      13.3 |       10.4 |       12.8 |
| mixed_240 |    289 |       9.4 |      14.9 |       17.2 |       17.9 |
