import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const SmartPenApp());
}

class SmartPenApp extends StatelessWidget {
  const SmartPenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Pen',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PracticeCanvas(),
    );
  }
}

// letter templates — normalised points from 0.0 to 1.0
// we'll scale them to fit the canvas at runtime


class LetterTemplates {
  static Map<String, List<Offset>> templates = {
    'O': _generateO(),
    'L': _generateL(),
    'C': _generateC(),
  };

  static List<Offset> _generateO() {
    final points = <Offset>[];
    for (int i = 0; i <= 60; i++) {
      final angle = (i / 60) * 2 * pi;
      points.add(Offset(
        0.5 + 0.3 * cos(angle),
        0.5 + 0.3 * sin(angle),
      ));
    }
    return points;
  }

  static List<Offset> _generateC() {
    final points = <Offset>[];
    for (int i = 0; i <= 50; i++) {
      final angle = (pi * 0.25) + (i / 50) * (pi * 1.5);
      points.add(Offset(
        0.5 + 0.3 * cos(angle),
        0.5 + 0.3 * sin(angle),
      ));
    }
    return points;
  }

  static List<Offset> _generateL() {
    final points = <Offset>[];
    for (int i = 0; i <= 30; i++) {
      points.add(Offset(0.38, 0.15 + i * (0.60 / 30)));
    }
    for (int i = 0; i <= 20; i++) {
      points.add(Offset(0.38 + i * (0.24 / 20), 0.75));
    }
    return points;
  }
}

class PracticeCanvas extends StatefulWidget {
  const PracticeCanvas({super.key});

  @override
  State<PracticeCanvas> createState() => _PracticeCanvasState();
}

class _PracticeCanvasState extends State<PracticeCanvas> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String _currentLetter = 'O';

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      if (_currentStroke.isNotEmpty) {
        _strokes.add(List.from(_currentStroke));
        print("Stroke done — ${_currentStroke.length} points");
      }
      _currentStroke = [];
    });
  }

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Trace the letter: $_currentLetter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearCanvas,
            tooltip: 'Clear',
          )
        ],
      ),
      // letter selector buttons
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['O', 'L', 'C'].map((letter) {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentLetter == letter
                    ? Colors.deepPurple
                    : Colors.grey[200],
              ),
              onPressed: () {
                setState(() {
                  _currentLetter = letter;
                  _strokes.clear();
                });
              },
              child: Text(
                letter,
                style: TextStyle(
                  color: _currentLetter == letter
                      ? Colors.white
                      : Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: CanvasPainter(
                strokes: _strokes,
                currentStroke: _currentStroke,
                templatePoints: LetterTemplates.templates[_currentLetter] ?? [],
                canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
              ),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent,
              ),
            );
          },
        ),
      ),
    );
  }
}

class CanvasPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final List<Offset> templatePoints;
  final Size canvasSize;

  CanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.templatePoints,
    required this.canvasSize,
  });

  // user stroke paint — solid black
  final Paint _strokePaint = Paint()
    ..color = Colors.black
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  // ghost template paint — faint blue
  final Paint _templatePaint = Paint()
    ..color = Colors.blue.withOpacity(0.2)
    ..strokeWidth = 28.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // draw ghost template first (underneath)
    _drawTemplate(canvas, size);

    // draw baseline and cap height guides
    _drawGuides(canvas, size);

    // draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, _strokePaint);
    }

    // draw current stroke
    _drawStroke(canvas, currentStroke, _strokePaint);
  }

  void _drawTemplate(Canvas canvas, Size size) {
    if (templatePoints.isEmpty) return;
    // use smaller dimension so circle stays circular on any screen
    final minDim = size.width < size.height ? size.width : size.height;
    final offsetX = (size.width - minDim) / 2;
    final offsetY = (size.height - minDim) / 2;
    final scaled = templatePoints
        .map((p) => Offset(
              offsetX + p.dx * minDim,
              offsetY + p.dy * minDim,
            ))
        .toList();
    _drawStroke(canvas, scaled, _templatePaint);
  }

  void _drawGuides(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // baseline at 90% height
    canvas.drawLine(
      Offset(20, size.height * 0.9),
      Offset(size.width - 20, size.height * 0.9),
      guidePaint,
    );

    // cap height at 10% height
    canvas.drawLine(
      Offset(20, size.height * 0.1),
      Offset(size.width - 20, size.height * 0.1),
      guidePaint,
    );
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) => true;
}