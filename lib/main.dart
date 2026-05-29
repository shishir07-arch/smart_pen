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
    var templateResampled = resample(templateStroke, n);

    // for circular strokes (O, C) rotate template to match user start point
    templateResampled = _alignStartPoint(userResampled, templateResampled);

    final userLength = pathLength(userStroke);
    final templateLength = pathLength(templateStroke);

    // position aware score
    double positionCost = 0;
    for (int i = 0; i < n; i++) {
      positionCost += (userResampled[i] - templateResampled[i]).distance;
    }
    final positionScore = (positionCost / (n * templateLength * 0.8)).clamp(0.0, 1.0);

    // shape score
    final userNorm = normalise(userResampled);
    final templateNorm = normalise(templateResampled);
    final rawShape = compute(userNorm, templateNorm);
    final shapeScore = (rawShape / 2.0).clamp(0.0, 1.0);

    // for circular letters rely more on shape, less on position
    // position matters more for L which has a fixed start
    final score = (positionScore * 0.3 + shapeScore * 0.7);

    
    final coverageRatio = userLength / templateLength;

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
    if (coverageRatio < 0.3) segment = 'incomplete';

    return {
      'score': score,
      'segment': segment,
      'coverage': coverageRatio,
      'positionScore': positionScore,
      'shapeScore': shapeScore,
    };
  }

  // rotate template points so the closest point to user's start becomes index 0
 static List<Offset> _alignStartPoint(
      List<Offset> user, List<Offset> template) {
    final userNorm = normalise(user);
    double minCost = double.infinity;
    int bestIndex = 0;

    for (int i = 0; i < template.length; i++) {
      final rotated = [...template.sublist(i), ...template.sublist(0, i)];
      final rotatedNorm = normalise(rotated);
      double cost = 0;
      for (int j = 0; j < template.length; j++) {
        cost += (userNorm[j] - rotatedNorm[j]).distance;
      }
      if (cost < minCost) {
        minCost = cost;
        bestIndex = i;
      }
    }

    if (bestIndex == 0) return template;
    return [...template.sublist(bestIndex), ...template.sublist(0, bestIndex)];
  }

  static double pathLength(List<Offset> points) {
    double length = 0;
    for (int i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    return length;
  }

  static String getTip(String segment, String letter, double coverage) {
    if (coverage < 0.3) {
      return 'Keep going — trace the full letter shape';
    }
    if (letter == 'O' || letter == 'C') {
      return 'Try to stay on the blue guide as you go around';
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
  
  // session config
  final List<String> _sessionLetters = ['O', 'C', 'L'];
  int _currentLetterIndex = 0;
  String get _currentLetter => _sessionLetters[_currentLetterIndex];

  // per letter tracking
  int _attemptCount = 0;
  int _failCount = 0;
  bool _tracingMode = false;

  // feedback
  String? _feedback;
  bool _isSuccess = false;
  bool _showStars = false;
  double _lastScore = -1;

  // session results — letter -> best score
  final Map<String, double> _sessionResults = {};

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

    // bounding box check
    final xs = _strokes.last.map((p) => p.dx).toList();
    final ys = _strokes.last.map((p) => p.dy).toList();
    final bWidth = xs.reduce(max) - xs.reduce(min);
    final bHeight = ys.reduce(max) - ys.reduce(min);
    final minDimension = minDim * 0.15;

    if (bWidth < minDimension || bHeight < minDimension) {
      setState(() {
        _feedback = 'Try drawing bigger — fill the blue guide';
        _isSuccess = false;
        _lastScore = 0;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _feedback = null);
      });
      return;
    }

    // minimum stroke length check
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

    print('position: ${result['positionScore']}, shape: ${result['shapeScore']}, coverage: $coverage, segment: $segment');

    _attemptCount++;

    // update best score for this letter
    final prev = _sessionResults[_currentLetter] ?? 1.0;
    _sessionResults[_currentLetter] = min(prev, score);

    if (score < 0.28) {
      print('MOCK BLE: sending H3 (success)');
      setState(() {
        _lastScore = score;
        _isSuccess = true;
        _showStars = true;
        _feedback = score < 0.15 ? '⭐ Perfect! Great job!' : '👍 Good job! Keep practising!';
        _failCount = 0;
      });
      // move to next letter after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _nextLetter();
      });
    } else {
      _failCount++;
      if (score < 0.35) {
        print('MOCK BLE: sending H1 (minor correction)');
      } else {
        print('MOCK BLE: sending H2 (major error)');
      }

      // after 3 fails drop to tracing mode
      if (_failCount >= 3 && !_tracingMode) {
        setState(() {
          _tracingMode = true;
          _feedback = 'No worries — just trace over the blue letter';
          _isSuccess = false;
          _lastScore = score;
        });
      } else {
        setState(() {
          _lastScore = score;
          _isSuccess = false;
          _feedback = _tracingMode
              ? 'Keep tracing — follow the blue guide'
              : DTW.getTip(segment, _currentLetter, coverage);
        });
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _feedback = null);
      });
    }
  }

  void _nextLetter() {
    if (_currentLetterIndex >= _sessionLetters.length - 1) {
      // session complete — go to summary
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionSummaryScreen(
            results: _sessionResults,
            letters: _sessionLetters,
          ),
        ),
      );
    } else {
      setState(() {
        _currentLetterIndex++;
        _strokes.clear();
        _currentStroke = [];
        _feedback = null;
        _isSuccess = false;
        _showStars = false;
        _lastScore = -1;
        _attemptCount = 0;
        _failCount = 0;
        _tracingMode = false;
      });
    }
  }

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _feedback = null;
      _isSuccess = false;
      _showStars = false;
      _lastScore = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_tracingMode
            ? 'Tracing mode: $_currentLetter'
            : 'Trace the letter: $_currentLetter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearCanvas,
            tooltip: 'Clear',
          )
        ],
      ),
      // progress indicator at top
      body: Column(
        children: [
          // letter progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _sessionLetters.asMap().entries.map((entry) {
                final i = entry.key;
                final letter = entry.value;
                final isDone = i < _currentLetterIndex;
                final isCurrent = i == _currentLetterIndex;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green.shade300
                          : isCurrent
                              ? Colors.deepPurple.shade200
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      letter,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDone || isCurrent
                            ? Colors.white
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // tracing mode banner
          if (_tracingMode)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Tracing mode — just follow the blue guide',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
              ),
            ),

          // canvas
          Expanded(
            child: Stack(
              children: [
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
                          canvasSize: Size(
                              constraints.maxWidth, constraints.maxHeight),
                          tracingMode: _tracingMode,
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

                // score
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _lastScore < 0
                          ? 'Score: —'
                          : 'Score: ${(100 - _lastScore * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                // attempt counter
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Attempt: $_attemptCount',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                // feedback popup
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

                // star burst
                if (_isSuccess && _showStars)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: StarBurstWidget(
                        onComplete: () {
                          setState(() => _showStars = false);
                        },
                      ),
                    ),
                  ),
              ],
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

   final bool tracingMode;

  CanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.templatePoints,
    required this.canvasSize,
    this.tracingMode = false,
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
    final paint = Paint()
      ..color = tracingMode
          ? Colors.orange.withOpacity(0.4)
          : Colors.blue.withOpacity(0.2)
      ..strokeWidth = tracingMode ? 36.0 : 28.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    _drawStroke(canvas, scaled, paint);
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

// ── Star Burst Animation ──────────────────────────────────────────
class StarBurstWidget extends StatefulWidget {
  final VoidCallback onComplete;
  const StarBurstWidget({super.key, required this.onComplete});

  @override
  State<StarBurstWidget> createState() => _StarBurstWidgetState();
}

class _StarBurstWidgetState extends State<StarBurstWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _stars = List.generate(20, (i) => _Star(
      x: 0.2 + _random.nextDouble() * 0.6,
      y: 0.1 + _random.nextDouble() * 0.7,
      size: 20 + _random.nextDouble() * 30,
      delay: _random.nextDouble() * 0.4,
      color: [
        Colors.amber,
        Colors.orange,
        Colors.yellow,
        Colors.deepOrange,
        Colors.purple,
      ][_random.nextInt(5)],
    ));

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: _stars.map((star) {
            final progress = ((_controller.value - star.delay) / (1 - star.delay))
                .clamp(0.0, 1.0);
            final opacity = progress < 0.7 ? progress / 0.7 : (1 - progress) / 0.3;
            final scale = 0.5 + progress * 1.5;
            final yOffset = -progress * 80;

            return Positioned(
              left: MediaQuery.of(context).size.width * star.x,
              top: MediaQuery.of(context).size.height * star.y + yOffset,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Text(
                    '⭐',
                    style: TextStyle(fontSize: star.size, color: star.color),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _Star {
  final double x, y, size, delay;
  final Color color;
  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.delay,
    required this.color,
  });
}

// ── Session Summary Screen ────────────────────────────────────────
class SessionSummaryScreen extends StatelessWidget {
  final Map<String, double> results;
  final List<String> letters;

  const SessionSummaryScreen({
    super.key,
    required this.results,
    required this.letters,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Session complete!')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎉 Great session!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Here\'s how you did:',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ...letters.map((letter) {
              final score = results[letter] ?? 1.0;
              final percent = ((1 - score) * 100).clamp(0, 100).toStringAsFixed(0);
              final color = score < 0.28
                  ? Colors.green
                  : score < 0.45
                      ? Colors.orange
                      : Colors.red;
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Letter $letter',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '$percent%',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: double.parse(percent) / 100,
                        backgroundColor: Colors.grey.shade200,
                        color: color,
                        minHeight: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PracticeCanvas()),
                  );
                },
                child: const Text(
                  'Start new session',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}