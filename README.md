# contour_gradient

A Flutter `ShapeBorder` that paints a gradient along the length of a border,
for any `OutlinedBorder` shape.

![Gradient borders on a star, rounded rectangle, circle, button and chip](https://raw.githubusercontent.com/bszarlej/contour_gradient/master/assets/showcase.gif)

A `SweepGradient` or a gradient background behind a padded child colors a
border by angle or by position in the box, so the colors bunch up on long
sides and stretch on short ones. `ContourGradientBorder` places colors by
distance along the border instead: a color at 0.5 sits exactly halfway around,
whatever the shape.

## Usage

`ContourGradientBorder` is an `OutlinedBorder`, so it works anywhere Flutter
accepts a shape. The outline comes from `shape`, and the width and alignment
come from `side`.

```dart
Container(
  width: 200,
  height: 80,
  decoration: const ShapeDecoration(
    shape: ContourGradientBorder(
      colors: [Colors.purple, Colors.blue, Colors.red],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      side: BorderSide(width: 3),
    ),
  ),
)
```

### Buttons and chips

`OutlinedButton` and `Chip` apply their own `side` to the shape, so set the
width there:

```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    shape: const ContourGradientBorder(
      colors: [Colors.purple, Colors.blue, Colors.red],
      shape: StadiumBorder(),
    ),
    side: const BorderSide(width: 2),
  ),
  onPressed: () {},
  child: const Text('Button'),
)
```

Other buttons, `Card` and `FloatingActionButton` use the border's own `side`.

### Text fields

`InputDecoration` takes an `InputBorder`, so text fields use
`ContourGradientInputBorder`. It takes the same `colors`, `stops`,
`startOffset` and `shape`, and leaves a gap in the top of the border for a
floating label, like `OutlineInputBorder`:

```dart
TextField(
  decoration: InputDecoration(
    labelText: 'Name',
    border: ContourGradientInputBorder(
      colors: [Colors.purple, Colors.blue, Colors.red],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  ),
)
```

The field applies its own `side`, so the border gets thicker when the field
has focus. The side's color is ignored, so an error does not change the
border's colors; set `errorBorder` and `focusedErrorBorder` to show errors.
The border also animates to and from an `OutlineInputBorder`, so you can use
one for some states and the other for the rest.

### Animation

`startOffset` moves the gradient along the border, as a fraction of its
length. Animating it from 0.0 to 1.0 moves the gradient once around, and
because 0.0 and 1.0 look the same, a repeating animation has no visible jump.
The example below repeats the first color at the end, so no hard edge travels
around the border either (see [How colors are placed](#how-colors-are-placed)).

```dart
class Spinning extends StatefulWidget {
  const Spinning({super.key});

  @override
  State<Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<Spinning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: 120,
        height: 120,
        decoration: ShapeDecoration(
          shape: ContourGradientBorder(
            colors: const [
              Colors.purple,
              Colors.blue,
              Colors.red,
              Colors.purple,
            ],
            startOffset: _controller.value,
            shape: const StarBorder(),
            side: const BorderSide(width: 4),
          ),
        ),
      ),
    );
  }
}
```

The border also interpolates, so `AnimatedContainer` and other implicit
animations can change its shape, width, colors and offset. It interpolates
with plain `OutlinedBorder`s too, which it treats as a single color.

## How colors are placed

- Position 0.0 is the point of the outline nearest the top-left corner of the
  box, and the gradient runs clockwise from there. On rounded rectangles it
  starts halfway around the top-left corner.
- The gradient runs from the first color to the last and does not blend back
  into the first, so where the end of the gradient meets its start the colors
  change in a hard edge. To blend back into the first color instead, repeat it
  at the end:

  ```dart
  ContourGradientBorder(
    colors: [Colors.purple, Colors.blue, Colors.red, Colors.purple],
  )
  ```

- Without `stops`, the colors are spaced evenly from 0.0 to 1.0. On a closed
  border the repeated first color joins up with itself across position 0.0,
  so it gets the same share of the border as each of the others.
- With `stops`, each color sits at its stop. Before the first stop the border
  is the first color, and after the last stop it is the last color. Two equal
  stops make a hard edge:

  ```dart
  ContourGradientBorder(
    colors: [Colors.red, Colors.red, Colors.blue, Colors.blue],
    stops: [0.0, 0.5, 0.5, 1.0],
  )
  ```

- A `LinearBorder` runs the gradient along only the edges it draws. Edges
  that meet at a corner form one line, which starts at its end nearest the
  top-left corner of the box: an underline runs left to right, and a start
  and bottom edge run down and then right. If all four edges meet, they form
  a loop like a rectangle. Separate lines, such as a top and a bottom edge,
  share the gradient one after the other.
- On an open line, such as an underline, the gradient runs from the first
  color at one end to the last color at the other. When `startOffset` moves
  it along, the colors that pass one end come back in at the other, so repeat
  the first color at the end here too to avoid a hard edge.
- A single color paints a plain border.

## Supported shapes

Any `OutlinedBorder` works, including `RoundedRectangleBorder`,
`StadiumBorder`, `CircleBorder`, `OvalBorder`, `StarBorder`,
`RoundedSuperellipseBorder`, `BeveledRectangleBorder`,
`ContinuousRectangleBorder`, `LinearBorder` and your own subclasses.

## Performance

Every border is painted by masking a colored band with the shape's own border,
so its edges match Flutter's exactly. That costs two `Canvas.saveLayer` calls
per paint.

For `RoundedRectangleBorder`, `StadiumBorder` and circular `CircleBorder`, the
band is quick to build and costs well under a millisecond of CPU time, even
when animated. Other shapes take about 1–2 ms per paint on a desktop machine.
That is fine for static borders, which are only painted when their area
repaints, and for a few animated ones. Animating many such borders at once can
drop frames on slower phones.

## Limitations

- Keep the border narrow compared to the shape's detail. When a border is so
  wide that it meets itself, as across the arms of a `StarBorder` or inside
  the curves of a rounded one, each part takes the color of the nearest part
  of the outline. The colors then meet at sharp seams, and a few pixels along
  them can be left uncolored.

## Example

The [example app](example/lib/main.dart) shows every supported shape,
buttons, cards, chips, text fields, animation, morphing and stops.
