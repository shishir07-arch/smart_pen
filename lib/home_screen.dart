import 'package:flutter/material.dart';
import 'main.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              // app title
              const Text(
                'Smart Pen',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Learning to write, one letter at a time',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              // mode buttons
              _ModeButton(
                label: 'Uppercase Letters',
                subtitle: 'Practice A to Z',
                icon: Icons.text_fields,
                color: Colors.deepPurple,
                onTap: () => _startSession(context, 'uppercase'),
              ),
              const SizedBox(height: 16),
              _ModeButton(
                label: 'Lowercase Letters',
                subtitle: 'Practice a to z',
                icon: Icons.font_download,
                color: Colors.teal,
                onTap: () => _startSession(context, 'lowercase'),
              ),
              const SizedBox(height: 16),
              _ModeButton(
                label: 'Sentence Practice',
                subtitle: 'Trace a full sentence',
                icon: Icons.short_text,
                color: Colors.orange,
                onTap: () => _startSession(context, 'sentence'),
              ),
              const Spacer(),
              // bottom note
              Center(
                child: Text(
                  'Tip: Follow the blue guide letter',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _startSession(BuildContext context, String mode) {
    List<String> letters;
    switch (mode) {
      case 'uppercase':
        letters = List.generate(26, (i) => String.fromCharCode(65 + i));
        break;
      case 'lowercase':
        letters = List.generate(26, (i) => String.fromCharCode(97 + i));
        break;
      case 'sentence':
        letters = 'the cat sat'.split('').where((c) => c != ' ').toList();
        break;
      default:
        letters = List.generate(26, (i) => String.fromCharCode(65 + i));
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeCanvas(sessionLetters: letters, mode: mode),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}