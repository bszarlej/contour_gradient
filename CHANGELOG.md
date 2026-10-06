## 1.2.3

* Separate edges of a `LinearBorder`, such as a top and a bottom edge, now
  each run the whole gradient, so they look alike. They used to share it one
  after the other. Edges that meet at a corner still form one line.

## 1.2.2

* Fixed `startOffset` moving the gradient anticlockwise, the opposite of
  what the documentation says. Increasing it now moves the gradient
  clockwise, so animations of it turn the other way than before: to keep the
  old direction, animate from 0.0 to -1.0 instead of to 1.0.

## 1.2.1

* Use contour_gradient version 1.2.0 in the example app

## 1.2.0

* Much faster animated borders. Geometry is cached and the gradient is
  applied on the GPU, and no Flutter shape needs `Canvas.saveLayer` any more:
  rounded, beveled and linear borders are clipped, and stroked shapes such as
  `StarBorder` are colored by a bundled fragment shader. On a Galaxy S24, 240
  animated stars went from 13 to over 100 frames per second, and from 1.6 GB
  of graphics memory to 159 MB. Custom shapes are still masked in layers.
* Borders now sample curves at the device's resolution.
* Fixed the inner edge of small `BeveledRectangleBorder`s.
* Edges may differ from 1.1.0 by a fraction of a pixel, which golden tests
  may notice. No API changes.

## 1.1.0

* Added `withGradient`, an extension on `OutlinedBorder` that paints any
  shape with a gradient along its border, keeping the shape's own side:
  `const StadiumBorder(side: BorderSide(width: 2)).withGradient(colors)`. The
  README and the example now use it. The `ContourGradientBorder` constructor
  is unchanged, and is still the way to make a `const` border.

## 1.0.3

* Added a showcase GIF to the package page on pub.dev.

## 1.0.2

* **Behavior change:** on closed borders the gradient no longer blends from
  the last color back into the first. It runs from the first color to the
  last, with a hard edge where its end meets its start. To keep the previous
  look, repeat the first color at the end of `colors`: with evenly spaced
  colors, `[a, b, c, a]` looks the same as `[a, b, c]` did before. With
  `stops`, the border is now the first color before the first stop and the
  last color after the last stop.

## 1.0.1

* Fixed a `BeveledRectangleBorder` shape's border being twice as wide as its
  side, as Flutter's own `BeveledRectangleBorder` paints it. It is now as wide
  as its side everywhere, on the bevels too.

## 1.0.0

Initial release.

* `ContourGradientBorder`: an `OutlinedBorder` that paints a gradient along
  the length of any `OutlinedBorder` shape. Supports `stops`, hard stops, and
  `startOffset` for moving the gradient along the border. On closed borders
  the gradient wraps around and evenly spaced colors each get the same share
  of the border.
* A `LinearBorder` shape runs the gradient along only the edges it draws, so
  an underline shows the whole gradient from left to right. Unlike Flutter's
  own `LinearBorder`, its edges are painted in the right place when the box
  does not start at the origin, as in a `Container`, and without a faint line
  where two edges meet.
* `ContourGradientInputBorder`: the same for `InputDecoration`, with a gap for
  floating labels like `OutlineInputBorder`.
* Both borders interpolate, so they work with implicit animations, and animate
  to and from plain `OutlinedBorder`s and `OutlineInputBorder`s.
