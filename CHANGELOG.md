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
