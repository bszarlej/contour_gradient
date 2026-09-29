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
