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

// ── Letter Templates ──────────────────────────────────────────────
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
      points.add(Offset(0.5 + 0.3 * cos(angle), 0.5 + 0.3 * sin(angle)));
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

  static List<Offset> _generateC() {
    final points = <Offset>[];
    for (int i = 0; i <= 50; i++) {
      final angle = (pi * 0.25) + (i / 50) * (pi * 1.5);
      points.add(Offset(0.5 + 0.3 * cos(angle), 0.5 + 0.3 * sin(angle)));
    }
    return points;
  }
}

// ── DTW Algorithm ─────────────────────────────────────────────────
class DTW {
  // resample a stroke to exactly n evenly spaced points
  static List<Offset> resample(List<Offset> points, int n) {
    if (points.length < 2) return points;

    // calculate total path length
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += (points[i] - points[i - 1]).distance;
    }

    final interval = totalLength / (n - 1);
    final resampled = <Offset>[points.first];
    double accumulated = 0;
    int i = 1;

    while (resampled.length < n && i < points.length) {
      final d = (points[i] - points[i - 1]).distance;
      if (accumulated + d >= interval) {
        final t = (interval - accumulated) / d;
        final newPoint = Offset(
          points[i - 1].dx + t * (points[i].dx - points[i - 1].dx),
          points[i - 1].dy + t * (points[i].dy - points[i - 1].dy),
        );
        resampled.add(newPoint);
        points = [newPoint, ...points.sublist(i)];
        i = 1;
        accumulated = 0;
      } else {
        accumulated += d;
        i++;
      }
    }

    while (resampled.length < n) {
      resampled.add(points.last);
    }

    return resampled;
  }

  // normalise points to start at origin and fit unit bounding box
  static List<Offset> normalise(List<Offset> points) {
    if (points.isEmpty) return points;

    // translate to origin
    final minX = points.map((p) => p.dx).reduce(min);
    final minY = points.map((p) => p.dy).reduce(min);
    final translated = points.map((p) => Offset(p.dx - minX, p.dy - minY)).toList();

    // scale to unit box
    final maxX = translated.map((p) => p.dx).reduce(max);
    final maxY = translated.map((p) => p.dy).reduce(max);
    final scale = max(maxX, maxY);
    if (scale == 0) return translated;

    return translated.map((p) => Offset(p.dx / scale, p.dy / scale)).toList();
  }

  // compute DTW distance between two equal-length point sequences
  static double compute(List<Offset> a, List<Offset> b) {
    final n = a.length;
    final matrix = List.generate(n, (_) => List.filled(n, double.infinity));
    matrix[0][0] = (a[0] - b[0]).distance;

    for (int i = 1; i < n; i++) {
      matrix[i][0] = matrix[i - 1][0] + (a[i] - b[0]).distance;
    }
    for (int j = 1; j < n; j++) {
      matrix[0][j] = matrix[0][j - 1] + (a[0] - b[j]).distance;
    }
    for (int i = 1; i < n; i++) {
      for (int j = 1; j < n; j++) {
        final cost = (a[i] - b[j]).distance;
        matrix[i][j] = cost +
            [matrix[i - 1][j], matrix[i][j - 1], matrix[i - 1][j - 1]]
                .reduce(min);
      }
    }

    return matrix[n - 1][n - 1] / n;
  }

  // returns score 0-1 and which segment had most error
static Map<String, dynamic> analyse(
      List<Offset> userStroke, List<Offset> templateStroke) {
    const n = 32;

    final userResampled = resample(userStroke, n);
    final templateResampled = resample(templateStroke, n);

    // position-aware score — compare WITHOUT normalising first
    // this catches drawing in wrong location
    double positionCost = 0;
    for (int i = 0; i < n; i++) {
      positionCost += (userResampled[i] - templateResampled[i]).distance;
    }
    // normalise position cost by canvas diagonal (~1000px typically)
    final positionScore = (positionCost / (n * 500)).clamp(0.0, 1.0);

    // shape score — normalised, catches wrong shape regardless of position
    final userNorm = normalise(userResampled);
    final templateNorm = normalise(templateResampled);
    final rawShape = compute(userNorm, templateNorm);
    final shapeScore = (rawShape / 2.0).clamp(0.0, 1.0);

    // combined score — weight position more
    final score = (positionScore * 0.6 + shapeScore * 0.4);

    // coverage check — did user actually draw enough points?
    final userLength = pathLength(userStroke);
    final templateLength = pathLength(templateStroke);
    final coverageRatio = userLength / templateLength;

    // find which third had most deviation
    final third = n ~/ 3;
    double startCost = 0, midCost = 0, endCost = 0;
    for (int i = 0; i < third; i++) {
      startCost += (userNorm[i] - templateNorm[i]).distance;
    }
    for (int i = third; i < third * 2; i++) {
      midCost += (userNorm[i] - templateNorm[i]).distance;
    }
    for (int i = third * 2; i < n; i++) {
      endCost += (userNorm[i] - templateNorm[i]).distance;
    }

    String segment = 'middle';
    if (startCost >= midCost && startCost >= endCost) segment = 'start';
    if (endCost >= midCost && endCost >= startCost) segment = 'end';

    // override segment if coverage is too low — they drew too little
    if (coverageRatio < 0.6) segment = 'incomplete';

    return {
      'score': score,
      'segment': segment,
      'coverage': coverageRatio,
      'positionScore': positionScore,
      'shapeScore': shapeScore,
    };
  }

  static double pathLength(List<Offset> points) {
    double length = 0;
    for (int i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    return length;
  }

  static String getTip(String segment, String letter, double coverage) {
    if (coverage < 0.5) {
      return 'Keep going — trace the full letter shape';
    }
    switch (segment) {
      case 'start':
        return 'Start right on the blue guide letter';
      case 'end':
        return 'Follow the blue guide all the way to the end';
      case 'middle':
        return 'Stay on the blue guide through the whole letter';
      default:
        return 'Try tracing right on the blue letter';
    }
  }
}

// ── Practice Canvas ───────────────────────────────────────────────
class PracticeCanvas extends StatefulWidget {
  const PracticeCanvas({super.key});

  @override
  State<PracticeCanvas> createState() => _PracticeCanvasState();
}

class _PracticeCanvasState extends State<PracticeCanvas> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String _currentLetter = 'O';
  String? _feedback;
  bool _isSuccess = false;
  double _lastScore = -1;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
      _feedback = null;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.length < 20) {
      setState(() => _currentStroke = []);
      return;
    }
    setState(() {
      _strokes.add(List.from(_currentStroke));
      _currentStroke = [];
    });
    _analyseStroke();
  }

void _analyseStroke() {
    final template = LetterTemplates.templates[_currentLetter];
    if (template == null) return;

    final size = MediaQuery.of(context).size;
    final minDim = min(size.width, size.height);
    final offsetX = (size.width - minDim) / 2;
    final offsetY = (size.height - minDim) / 2;
    final scaledTemplate = template
        .map((p) => Offset(offsetX + p.dx * minDim, offsetY + p.dy * minDim))
        .toList();

    // minimum stroke length check — must be at least 15% of template length
    final userLength = DTW.pathLength(_strokes.last);
    final templateLength = DTW.pathLength(scaledTemplate);
    if (userLength < templateLength * 0.15) {
      setState(() {
        _feedback = 'That was too short — try drawing the full letter';
        _isSuccess = false;
        _lastScore = 0;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _feedback = null);
      });
      return;
    }

    final result = DTW.analyse(_strokes.last, scaledTemplate);
    final score = result['score'] as double;
    final segment = result['segment'] as String;
    final coverage = result['coverage'] as double;

    if (score < 0.15) {
      print('MOCK BLE: sending H3 (success)');
    } else if (score < 0.4) {
      print('MOCK BLE: sending H1 (minor correction)');
    } else {
      print('MOCK BLE: sending H2 (major error)');
    }

    setState(() {
      _lastScore = score;
      if (score < 0.15) {
        _isSuccess = true;
        _feedback = '⭐ Perfect! Great job!';
      } else {
        _isSuccess = false;
        _feedback = DTW.getTip(segment, _currentLetter, coverage);
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _feedback = null;
      _isSuccess = false;
      _lastScore = -1; // -1 means no score yet
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
                  _feedback = null;
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
      body: Stack(
        children: [
          // drawing canvas
          GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  painter: CanvasPainter(
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                    templatePoints:
                        LetterTemplates.templates[_currentLetter] ?? [],
                    canvasSize:
                        Size(constraints.maxWidth, constraints.maxHeight),
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

          // score indicator top right
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _lastScore < 0 ? 'Score: —' : 'Score: ${(100 - _lastScore * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          // feedback popup at bottom
          if (_feedback != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _feedback != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isSuccess
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Text(
                    _feedback!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _isSuccess
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Canvas Painter ────────────────────────────────────────────────
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

  final Paint _strokePaint = Paint()
    ..color = Colors.black
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final Paint _templatePaint = Paint()
    ..color = Colors.blue.withOpacity(0.2)
    ..strokeWidth = 28.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTemplate(canvas, size);
    _drawGuides(canvas, size);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, _strokePaint);
    }
    _drawStroke(canvas, currentStroke, _strokePaint);
  }

  void _drawTemplate(Canvas canvas, Size size) {
    if (templatePoints.isEmpty) return;
    final minDim = min(size.width, size.height);
    final offsetX = (size.width - minDim) / 2;
    final offsetY = (size.height - minDim) / 2;
    final scaled = templatePoints
        .map((p) => Offset(offsetX + p.dx * minDim, offsetY + p.dy * minDim))
        .toList();
    _drawStroke(canvas, scaled, _templatePaint);
  }

  void _drawGuides(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(20, size.height * 0.9),
        Offset(size.width - 20, size.height * 0.9), guidePaint);
    canvas.drawLine(Offset(20, size.height * 0.1),
        Offset(size.width - 20, size.height * 0.1), guidePaint);
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