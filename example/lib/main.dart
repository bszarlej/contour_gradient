import 'package:contour_gradient/contour_gradient.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

const List<Color> _sunset = <Color>[
  Color(0xFF7F00FF),
  Color(0xFF00C6FF),
  Color(0xFFFF4E50),
  Color(0xFF7F00FF),
];

const List<Color> _aurora = <Color>[
  Color(0xFF00F260),
  Color(0xFF0575E6),
  Color(0xFFE100FF),
  Color(0xFFFFC300),
  Color(0xFF00F260),
];

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contour Gradient',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contour Gradient')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        shape: const ContourGradientBorder(
          colors: _aurora,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          side: BorderSide(width: 2),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: const <Widget>[
          _Section(
            title: 'Shapes',
            description:
                'Any OutlinedBorder can be used as the shape. The gradient '
                'follows the outline, so each color gets the same share of '
                'it whatever the shape.',
            child: _ShapesGallery(),
          ),
          _Section(
            title: 'Buttons',
            description:
                'Buttons apply their own side to the shape, so set the width '
                'with the style\'s side.',
            child: _Buttons(),
          ),
          _Section(title: 'Cards, chips and inputs', child: _MaterialWidgets()),
          _Section(
            title: 'Animated start offset',
            description:
                'Animating startOffset from 0.0 to 1.0 moves the gradient '
                'once around the border, and repeats seamlessly.',
            child: _RotatingBorders(),
          ),
          _Section(
            title: 'Morphing shapes',
            description:
                'ContourGradientBorder lerps, so AnimatedContainer can morph '
                'between shapes, widths and gradients. Tap to change.',
            child: _MorphingBorder(),
          ),
          _Section(
            title: 'Stops',
            description:
                'Stops place colors along the border. Equal stops make a '
                'hard edge.',
            child: _Stops(),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.description, required this.child});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: text.titleLarge),
          if (description != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(description!, style: text.bodyMedium),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// A labelled box painted with [shape].
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.label,
    required this.shape,
    this.colors = _sunset,
    this.width = 120,
    this.height = 80,
    this.startOffset = 0.0,
    this.stops,
  });

  final String label;
  final OutlinedBorder shape;
  final List<Color> colors;
  final List<double>? stops;
  final double width;
  final double height;
  final double startOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: width,
          height: height,
          decoration: ShapeDecoration(
            shape: ContourGradientBorder(
              colors: colors,
              stops: stops,
              startOffset: startOffset,
              shape: shape,
              side: const BorderSide(width: 4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _ShapesGallery extends StatelessWidget {
  const _ShapesGallery();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 24,
      runSpacing: 24,
      children: <Widget>[
        _ShapeTile(label: 'Rectangle', shape: RoundedRectangleBorder()),
        _ShapeTile(
          label: 'Rounded rectangle',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        _ShapeTile(label: 'Stadium', shape: StadiumBorder()),
        _ShapeTile(
          label: 'Beveled',
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        _ShapeTile(label: 'Circle', shape: CircleBorder(), width: 80),
        _ShapeTile(label: 'Oval', shape: OvalBorder()),
        _ShapeTile(
          label: 'Superellipse',
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
        _ShapeTile(
          label: 'Star',
          shape: StarBorder(innerRadiusRatio: 0.45),
          width: 90,
          height: 90,
        ),
        _ShapeTile(
          label: 'Rounded star',
          shape: StarBorder(
            points: 7,
            innerRadiusRatio: 0.65,
            pointRounding: 0.5,
            valleyRounding: 0.3,
          ),
          width: 90,
          height: 90,
        ),
        _ShapeTile(
          label: 'Hexagon',
          shape: StarBorder.polygon(sides: 6, pointRounding: 0.2),
          width: 90,
          height: 90,
        ),
        // A LinearBorder runs the gradient along only the edges it draws.
        _ShapeTile(
          label: 'Linear, bottom',
          shape: LinearBorder(bottom: LinearBorderEdge()),
        ),
        _ShapeTile(
          label: 'Linear, top and bottom',
          shape: LinearBorder(
            bottom: LinearBorderEdge(),
            top: LinearBorderEdge(),
          ),
        ),
        _ShapeTile(
          label: 'Linear, start and bottom',
          shape: LinearBorder(
            start: LinearBorderEdge(),
            bottom: LinearBorderEdge(),
          ),
        ),
        _ShapeTile(
          label: 'Linear, half bottom',
          shape: LinearBorder(bottom: LinearBorderEdge(size: 0.5)),
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: const ContourGradientBorder(
              colors: _sunset,
              shape: StadiumBorder(),
            ),
            side: const BorderSide(width: 2),
          ),
          onPressed: () {},
          child: const Text('OutlinedButton'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            shape: const ContourGradientBorder(
              colors: _aurora,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            side: const BorderSide(width: 2),
          ),
          onPressed: () {},
          icon: const Icon(Icons.auto_awesome),
          label: const Text('With icon'),
        ),
        IconButton(
          style: IconButton.styleFrom(
            shape: const ContourGradientBorder(
              colors: _aurora,
              shape: CircleBorder(),
              side: BorderSide(width: 2),
            ),
          ),
          onPressed: () {},
          icon: const Icon(Icons.favorite),
        ),
      ],
    );
  }
}

class _MaterialWidgets extends StatelessWidget {
  const _MaterialWidgets();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Card(
          shape: ContourGradientBorder(
            colors: _sunset,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            side: BorderSide(width: 2),
          ),
          child: ListTile(
            leading: Icon(Icons.gradient),
            title: Text('Card'),
            subtitle: Text('A Card with a gradient border.'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String label in <String>['Chip', 'Another', 'Third'])
              Chip(
                label: Text(label),
                // Chips apply their own side to the shape.
                side: const BorderSide(width: 1.5),
                shape: const ContourGradientBorder(
                  colors: _aurora,
                  shape: StadiumBorder(),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.bolt, size: 18),
              label: const Text('ActionChip'),
              onPressed: () {},
              side: const BorderSide(width: 1.5),
              shape: const ContourGradientBorder(
                colors: _sunset,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Text fields take a ContourGradientInputBorder. The field applies
        // its own side, so the border gets thicker when focused, and a
        // floating label gets a gap in the top of the border.
        const TextField(
          decoration: InputDecoration(
            labelText: 'Name',
            border: ContourGradientInputBorder(
              colors: _sunset,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const TextField(
          decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: Icon(Icons.search),
            border: ContourGradientInputBorder(
              colors: _aurora,
              shape: StadiumBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RotatingBorders extends StatefulWidget {
  const _RotatingBorders();

  @override
  State<_RotatingBorders> createState() => _RotatingBordersState();
}

class _RotatingBordersState extends State<_RotatingBorders>
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
      builder: (BuildContext context, Widget? child) {
        final double offset = _controller.value;
        return Wrap(
          spacing: 24,
          runSpacing: 24,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _ShapeTile(
              label: 'Stadium',
              shape: const StadiumBorder(),
              colors: _aurora,
              startOffset: offset,
            ),
            _ShapeTile(
              label: 'Star',
              shape: const StarBorder(innerRadiusRatio: 0.45),
              width: 90,
              height: 90,
              startOffset: offset,
            ),
            // A single bright streak chasing around the border.
            _ShapeTile(
              label: 'Streak',
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              colors: const <Color>[
                Color(0x3300C6FF),
                Color(0x3300C6FF),
                Color(0xFF00C6FF),
                Color(0x3300C6FF),
              ],
              stops: const <double>[0.0, 0.7, 0.85, 1.0],
              startOffset: offset,
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: ContourGradientBorder(
                  colors: _sunset,
                  startOffset: offset,
                  shape: const StadiumBorder(),
                ),
                side: const BorderSide(width: 2),
              ),
              onPressed: () {},
              child: const Text('Animated button'),
            ),
          ],
        );
      },
    );
  }
}

class _MorphingBorder extends StatefulWidget {
  const _MorphingBorder();

  @override
  State<_MorphingBorder> createState() => _MorphingBorderState();
}

class _MorphingBorderState extends State<_MorphingBorder> {
  static const List<ContourGradientBorder> _borders = <ContourGradientBorder>[
    ContourGradientBorder(
      colors: _sunset,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      side: BorderSide(width: 3),
    ),
    ContourGradientBorder(
      colors: _aurora,
      shape: StadiumBorder(),
      side: BorderSide(width: 8),
    ),
    ContourGradientBorder(
      colors: _sunset,
      startOffset: 0.5,
      shape: StarBorder(innerRadiusRatio: 0.5),
      side: BorderSide(width: 5),
    ),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _index = (_index + 1) % _borders.length),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        width: 200,
        height: 120,
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: _borders[_index]),
        child: const Text('Tap me'),
      ),
    );
  }
}

class _Stops extends StatelessWidget {
  const _Stops();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 24,
      runSpacing: 24,
      children: <Widget>[
        _ShapeTile(
          label: 'Custom stops',
          shape: StadiumBorder(),
          colors: <Color>[Colors.pink, Colors.orange],
          stops: <double>[0.0, 0.3],
        ),
        _ShapeTile(
          label: 'Hard stops',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          colors: <Color>[Colors.red, Colors.red, Colors.blue, Colors.blue],
          stops: <double>[0.0, 0.5, 0.5, 1.0],
        ),
        _ShapeTile(
          label: 'Single color',
          shape: StadiumBorder(),
          colors: <Color>[Colors.teal],
        ),
      ],
    );
  }
}
