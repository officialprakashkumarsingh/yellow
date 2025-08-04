import 'dart:async';
import 'package:flutter/material.dart';

class LiveActivityIndicator extends StatefulWidget {
  final String initialLabel;
  final List<String> activities;
  final IconData icon;

  const LiveActivityIndicator({
    super.key,
    required this.initialLabel,
    required this.activities,
    required this.icon,
  });

  @override
  State<LiveActivityIndicator> createState() => _LiveActivityIndicatorState();
}

class _LiveActivityIndicatorState extends State<LiveActivityIndicator> with TickerProviderStateMixin {
  late final AnimationController _breathingController;
  late final Animation<double> _breathingAnimation;
  late final Timer _activityTimer;
  
  late List<String> _allActivities;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _allActivities = [widget.initialLabel, ...widget.activities];

    // Breathing animation for the icon
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _breathingAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    // Timer to cycle through activity labels
    _activityTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _allActivities.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _activityTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _breathingAnimation,
              child: Icon(
                widget.icon,
                size: 18,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.5),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                _allActivities[_currentIndex],
                key: ValueKey<String>(_allActivities[_currentIndex]),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}