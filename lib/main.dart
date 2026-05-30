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
      points.add(Offset(0.5 + 0.2 * cos(angle), 0.5 + 0.3 * sin(angle)));
    }
    return points;
  }

  static List<Offset> _generateL() {
    final points = <Offset>[];
    for (int i = 0; i <= 30; i++) {
      points.add(Offset(0.4, 0.25 + i * (0.40 / 30)));
    }
    for (int i = 0; i <= 20; i++) {
      points.add(Offset(0.4 + i * (0.18 / 20), 0.65));
    }
    return points;
  }

  static List<Offset> _generateC() {
    final points = <Offset>[];
    for (int i = 0; i <= 50; i++) {
      final angle = (pi * 0.25) + (i / 50) * (pi * 1.5);
      points.add(Offset(0.5 + 0.2 * cos(angle), 0.5 + 0.3 * sin(angle)));
    }
    return points;
  }
}

// ── DTW Algorithm ─────────────────────────────────────────────────
class DTW {
  static List<Offset> resample(List<Offset> points, int n) {
    if (points.length < 2) return points;
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
    while (resampled.length < n) resampled.add(points.last);
    return resampled;
  }

  static double pathLength(List<Offset> points) {
    double length = 0;
    for (int i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    return length;
  }

  // core check — what % of user points are within tolerance of template
  static double proximityScore(
      List<Offset> userStroke, List<Offset> templateStroke, double tolerance) {
    if (userStroke.isEmpty) return 0;
    int onPath = 0;
    for (final point in userStroke) {
      // find closest template point
      double minDist = double.infinity;
      for (final tp in templateStroke) {
        final d = (point - tp).distance;
        if (d < minDist) minDist = d;
      }
      if (minDist <= tolerance) onPath++;
    }
    return onPath / userStroke.length;
  }

  // coverage — what % of template is covered by user stroke
  static double templateCoverage(
      List<Offset> userStroke, List<Offset> templateStroke, double tolerance) {
    if (templateStroke.isEmpty) return 0;
    int covered = 0;
    for (final tp in templateStroke) {
      for (final point in userStroke) {
        if ((point - tp).distance <= tolerance) {
          covered++;
          break;
        }
      }
    }
    return covered / templateStroke.length;
  }

  static Map<String, dynamic> analyse(
      List<Offset> userStroke, List<Offset> templateStroke) {
    const n = 64;
    final userResampled = resample(userStroke, n);
    final templateResampled = resample(templateStroke, n);

    // tolerance = half the template stroke width on screen (~14px)
    final tolerance = pathLength(templateResampled) * 0.12;

    // what % of user points are on the template path
    final onPath = proximityScore(userResampled, templateResampled, tolerance);

    // what % of template is covered by user
    final coverage = templateCoverage(userResampled, templateResampled, tolerance);

    // score = combination of both
    // onPath catches squiggles outside (they won't be on path)
    // coverage catches incomplete strokes (half L won't cover template)
    final score = (onPath * 0.5 + coverage * 0.5);

    // segment detection — which third has least coverage
    final third = templateResampled.length ~/ 3;
    double startCov = 0, midCov = 0, endCov = 0;
    for (int i = 0; i < third; i++) {
      for (final p in userResampled) {
        if ((p - templateResampled[i]).distance <= tolerance) {
          startCov++;
          break;
        }
      }
    }
    for (int i = third; i < third * 2; i++) {
      for (final p in userResampled) {
        if ((p - templateResampled[i]).distance <= tolerance) {
          midCov++;
          break;
        }
      }
    }
    for (int i = third * 2; i < templateResampled.length; i++) {
      for (final p in userResampled) {
        if ((p - templateResampled[i]).distance <= tolerance) {
          endCov++;
          break;
        }
      }
    }

    String segment = 'middle';
    if (startCov <= midCov && startCov <= endCov) segment = 'start';
    if (endCov <= midCov && endCov <= startCov) segment = 'end';

    return {
      'score': score,
      'onPath': onPath,
      'coverage': coverage,
      'segment': segment,
    };
  }

  static List<Offset> normalise(List<Offset> points) {
    if (points.isEmpty) return points;
    final minX = points.map((p) => p.dx).reduce(min);
    final minY = points.map((p) => p.dy).reduce(min);
    final translated = points.map((p) => Offset(p.dx - minX, p.dy - minY)).toList();
    final maxX = translated.map((p) => p.dx).reduce(max);
    final maxY = translated.map((p) => p.dy).reduce(max);
    final scale = max(maxX, maxY);
    if (scale == 0) return translated;
    return translated.map((p) => Offset(p.dx / scale, p.dy / scale)).toList();
  }

  static String getTip(String segment, String letter, double coverage, bool tracingMode) {
    if (tracingMode) return 'Follow the orange guide';
    if (coverage < 0.4) return 'Keep going — trace the full letter';
    switch (segment) {
      case 'start': return 'Try starting right on the letter';
      case 'end': return 'Follow the guide all the way to the end';
      default: return 'Stay on the blue guide through the middle';
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

  double _difficultyMultiplier = 1.0; // starts normal, adjusts over time
  int _tracingSecondsLeft = 60;
  bool _showTracingChoice = false;

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
    // auto clear strokes after analysis so canvas stays clean
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _strokes.clear());
    });
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
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _feedback = null);
      });
      return;
    }

    // check if stroke is near the template at all
    final strokeCenterX = (xs.reduce(max) + xs.reduce(min)) / 2;
    final strokeCenterY = (ys.reduce(max) + ys.reduce(min)) / 2;
    final templateCenterX = scaledTemplate.map((p) => p.dx).reduce((a, b) => a + b) / scaledTemplate.length;
    final templateCenterY = scaledTemplate.map((p) => p.dy).reduce((a, b) => a + b) / scaledTemplate.length;
    final distFromTemplate = sqrt(
      pow(strokeCenterX - templateCenterX, 2) +
      pow(strokeCenterY - templateCenterY, 2)
    );

    if (distFromTemplate > minDim * 0.35) {
      setState(() {
        _feedback = 'Draw on the letter — stay on the guide';
        _isSuccess = false;
        _lastScore = 0;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _feedback = null);
      });
      return;
    }

    // size check — user stroke must be similar size to template
    final userWidth = xs.reduce(max) - xs.reduce(min);
    final userHeight = ys.reduce(max) - ys.reduce(min);
    final templateXs = scaledTemplate.map((p) => p.dx).toList();
    final templateYs = scaledTemplate.map((p) => p.dy).toList();
    final templateWidth = templateXs.reduce(max) - templateXs.reduce(min);
    final templateHeight = templateYs.reduce(max) - templateYs.reduce(min);
    
    final widthRatio = userWidth / templateWidth;
    final heightRatio = userHeight / templateHeight;

    if (widthRatio < 0.4 || heightRatio < 0.4) {
      setState(() {
        _feedback = 'Draw bigger — try to fill the whole blue letter';
        _isSuccess = false;
        _lastScore = 0;
      });
      Future.delayed(const Duration(seconds: 2), () {
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

    

    // update best score for this letter
    _attemptCount++;

    // update best score for this letter
     final prev = _sessionResults[_currentLetter] ?? 0.0;
    _sessionResults[_currentLetter] = max(prev, score);

    // dynamic difficulty adjustment
    if (score >= 0.65 / _difficultyMultiplier) {
      _difficultyMultiplier = (_difficultyMultiplier + 0.05).clamp(0.8, 1.3);
    } else {
      _difficultyMultiplier = (_difficultyMultiplier - 0.05).clamp(0.8, 1.3);
    }

    // score is now 0-1 where 1 = perfect, 0 = completely wrong
    // flip multiplier logic too
    final threshold = 0.72 / _difficultyMultiplier;

    if (score >= threshold) {
      print('MOCK BLE: sending H3 (success) — onPath: ${result['onPath']}, coverage: ${result['coverage']}');
      setState(() {
        _lastScore = score;
        _isSuccess = true;
        _showStars = true;
        _feedback = score > 0.85 ? '⭐ Perfect! Great job!' : '👍 Good job! Keep practising!';
        _failCount = 0;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _nextLetter();
      });
    } else {
      _failCount++;
      if (score >= 0.4) {
        print('MOCK BLE: sending H1 (minor)');
      } else {
        print('MOCK BLE: sending H2 (major error)');
      }

      if (_failCount >= 3 && !_tracingMode) {
        setState(() {
          _tracingMode = true;
          _feedback = 'No worries — just trace over the orange letter';
          _isSuccess = false;
          _lastScore = score;
        });
        _startTracingTimer();
      } else {
        setState(() {
          _lastScore = score;
          _isSuccess = false;
          _feedback = DTW.getTip(segment, _currentLetter, coverage, _tracingMode);
        });
      }

      Future.delayed(const Duration(milliseconds: 1500), () {
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

  void _startTracingTimer() {
    _tracingSecondsLeft = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_tracingMode) return false;
      setState(() => _tracingSecondsLeft--);
      if (_tracingSecondsLeft <= 0) {
        setState(() => _showTracingChoice = true);
        return false;
      }
      return true;
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
                          : 'Score: ${(_lastScore * 100).toStringAsFixed(0)}%',
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

                if (_showTracingChoice)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(32),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Good effort! What would you like to do?',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showTracingChoice = false;
                                    _tracingSecondsLeft = 60;
                                  });
                                  _startTracingTimer();
                                },
                                child: const Text('Keep tracing', style: TextStyle(color: Colors.white)),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showTracingChoice = false;
                                    _tracingMode = false;
                                    _failCount = 0;
                                    _strokes.clear();
                                  });
                                },
                                child: const Text('Try on my own', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
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

  // final Paint _templatePaint = Paint()
  //   ..color = Colors.blue.withOpacity(0.2)
  //   ..strokeWidth = 28.0
  //   ..strokeCap = StrokeCap.round
  //   ..style = PaintingStyle.stroke;

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
              final percent = (score * 100).clamp(0, 100).toStringAsFixed(0);
              final color = score > 0.72
                  ? Colors.green
                  : score > 0.5
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