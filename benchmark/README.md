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

## 1.2.0, step 1: cached geometry, GPU gradient

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

## 1.2.0, step 2: rounded rectangles clipped, not masked

Same device and conditions. Rounded rectangles, stadiums and circles are now
clipped to their area instead of masked in two layers; other shapes still use
the layers.

`paint()` cost, µs per border:

| Rounded rectangle | Stadium | Beveled | Superellipse | Oval | Star |
| ----------------: | ------: | ------: | -----------: | ---: | ---: |
|                 6 |       4 |      13 |           14 |   10 |   14 |

Frame timings, ms:

| Scenario  | Frames | Build avg | Build p99 | Raster avg | Raster p99 |
| --------- | -----: | --------: | --------: | ---------: | ---------: |
| rrect_24  |    611 |       1.6 |       2.3 |        2.7 |        4.2 |
| rrect_96  |    585 |       3.6 |      10.2 |        4.5 |        5.4 |
| rrect_240 |    562 |       5.2 |      11.5 |        5.6 |        6.3 |
| star_24   |    598 |       1.1 |       1.4 |        5.8 |        6.5 |
| star_96   |    537 |       5.0 |       9.7 |        8.6 |        9.2 |
| star_240  |    245 |      10.0 |      15.9 |       20.2 |       22.9 |
| mixed_24  |    611 |       1.1 |       1.5 |        5.4 |        8.5 |
| mixed_96  |    575 |       4.8 |      10.2 |        6.4 |        7.0 |
| mixed_240 |    325 |       8.4 |      14.1 |       13.5 |       14.2 |

Graphics memory with 240 animated borders on screen, from the `Graphics` line
of `adb shell dumpsys meminfo com.example.contour_gradient_example` while
`lib/benchmark.dart` runs; the app drawing no borders at all uses 142 MB:

| Shape             | Masked in two layers | Clipped |
| ----------------- | -------------------: | ------: |
| Rounded rectangle |             1,561 MB |  151 MB |
| Stadium           |                    — |  151 MB |
| Star              |             1,756 MB |       — |

Each layer costs a few megabytes per border on Impeller, far more than the
border's pixels, so layers, not geometry, dominate memory.

## 1.2.0, step 3: bevels and linear borders clipped too

Same device and conditions. Beveled and linear borders get bands that follow
their corners exactly, and are clipped like rounded rectangles. Only shapes
that stroke their border (star, oval, superellipse, continuous rectangle)
still use layers.

`paint()` cost, µs per border:

| Rounded rectangle | Stadium | Beveled | Superellipse | Oval | Star |
| ----------------: | ------: | ------: | -----------: | ---: | ---: |
|                 6 |       5 |       5 |           13 |    9 |   14 |

Frame timings, ms:

| Scenario  | Frames | Build avg | Build p99 | Raster avg | Raster p99 |
| --------- | -----: | --------: | --------: | ---------: | ---------: |
| rrect_24  |    611 |       1.5 |       2.2 |        2.7 |        3.8 |
| rrect_96  |    585 |       3.5 |       9.4 |        4.4 |        5.3 |
| rrect_240 |    565 |       4.9 |      10.9 |        5.6 |        6.9 |
| star_24   |    598 |       1.1 |       1.4 |        5.9 |        6.7 |
| star_96   |    569 |       5.3 |      10.1 |        8.4 |        8.8 |
| star_240  |    257 |      11.0 |      17.2 |       19.2 |       19.9 |
| mixed_24  |    598 |       1.2 |       1.5 |        5.4 |        6.1 |
| mixed_96  |    589 |       4.2 |       9.9 |        5.9 |       10.9 |
| mixed_240 |    351 |       8.0 |      17.9 |       10.8 |       19.5 |

Graphics memory with 240 animated bevels on screen: 1,677 MB masked in two
layers, 148 MB clipped.

## 1.2.0: stroked shapes shaded

Same device and conditions. Shapes that stroke their outline paint their own
border with a fragment shader that looks up how far along the border each
pixel is, instead of being masked in two layers. No border uses layers any
more once the shader and its image have loaded.

`paint()` cost, µs per border, once the shader and its image have loaded:

| Rounded rectangle | Stadium | Beveled | Superellipse | Oval | Star |
| ----------------: | ------: | ------: | -----------: | ---: | ---: |
|                 6 |       5 |       6 |            9 |    5 |   10 |

Frame timings, ms:

| Scenario  | Frames | Build avg | Build p99 | Raster avg | Raster p99 |
| --------- | -----: | --------: | --------: | ---------: | ---------: |
| rrect_24  |    610 |       1.6 |       2.0 |        2.7 |        3.7 |
| rrect_96  |    583 |       3.6 |       9.1 |        4.5 |        5.5 |
| rrect_240 |    555 |       5.2 |      11.2 |        5.7 |        6.5 |
| star_24   |    592 |       2.3 |       2.9 |        2.3 |        3.1 |
| star_96   |    580 |       4.4 |      11.1 |        2.7 |        4.0 |
| star_240  |    531 |       5.9 |      12.9 |        2.9 |        4.2 |
| mixed_24  |    608 |       2.1 |       2.6 |        2.9 |        4.0 |
| mixed_96  |    588 |       3.7 |       8.7 |        3.8 |        5.6 |
| mixed_240 |    566 |       5.7 |      12.5 |        5.0 |        6.3 |

Graphics memory with 240 animated stars on screen: 1,756 MB masked in two
layers, 159 MB shaded.

The image a shaded border needs is built on its second paint at a given
size, so the first paint of a shape at a new size costs what it did before:
in the debug-mode stage benchmark, about 1.1 ms for a superellipse and 1.4
ms for a star. Building the image when the border is first painted would
have made that about 3.6 to 4.0 ms, on every frame of an animation of the
border's size.
