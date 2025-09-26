import 'package:flutter/material.dart';
import 'dart:math';

class AudioLevelVisualizer extends StatefulWidget {
  final List<double> audioLevels;
  final int barCount;
  final double maxHeight;
  final Color baseColor;
  final bool isActive;

  const AudioLevelVisualizer({
    super.key,
    required this.audioLevels,
    this.barCount = 12,
    this.maxHeight = 40,
    this.baseColor = Colors.blue,
    this.isActive = true,
  });

  @override
  State<AudioLevelVisualizer> createState() => _AudioLevelVisualizerState();
}

class _AudioLevelVisualizerState extends State<AudioLevelVisualizer> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  List<double> _currentHeights = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void didUpdateWidget(AudioLevelVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioLevels != oldWidget.audioLevels) {
      _updateAnimations();
    }
  }

  void _initializeAnimations() {
    _currentHeights = List.generate(widget.barCount, (index) => 2.0);
    
    _controllers = List.generate(widget.barCount, (index) {
      return AnimationController(
        duration: const Duration(milliseconds: 100),
        vsync: this,
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 2.0, end: widget.maxHeight).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOut),
      );
    }).toList();

    // Инициализируем случайные высоты
    if (widget.isActive) {
      _startIdleAnimation();
    }
  }

  void _startIdleAnimation() {
    for (int i = 0; i < widget.barCount; i++) {
      _animateBarTo(i, 2.0 + Random().nextDouble() * 5);
    }
  }

  void _updateAnimations() {
    if (widget.audioLevels.isEmpty) return;

    // Распределяем уровни звука по барам
    for (int i = 0; i < widget.barCount; i++) {
      final levelIndex = i % widget.audioLevels.length;
      final targetHeight = 2.0 + (widget.audioLevels[levelIndex] * widget.maxHeight);
      _animateBarTo(i, targetHeight);
    }
  }

  void _animateBarTo(int index, double targetHeight) {
    final controller = _controllers[index];
    
    _currentHeights[index] = targetHeight;
    
    controller.animateTo(
      targetHeight / widget.maxHeight,
      duration: const Duration(milliseconds: 100),
    );
  }

  Color _getBarColor(double height) {
    final ratio = height / widget.maxHeight;
    
    if (ratio < 0.3) {
      return widget.baseColor.withOpacity(0.6);
    } else if (ratio < 0.6) {
      return widget.baseColor;
    } else {
      return Colors.red;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Container(
                width: 3,
                height: _animations[index].value,
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                decoration: BoxDecoration(
                  color: _getBarColor(_animations[index].value),
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    if (_animations[index].value > widget.maxHeight * 0.3)
                      BoxShadow(
                        color: _getBarColor(_animations[index].value).withOpacity(0.3),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                  ],
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
