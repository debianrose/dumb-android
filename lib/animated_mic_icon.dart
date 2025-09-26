import 'package:flutter/material.dart';

class AnimatedMicIcon extends StatefulWidget {
  final bool isRecording;
  final double size;
  final Color color;

  const AnimatedMicIcon({
    super.key,
    required this.isRecording,
    this.size = 24,
    this.color = Colors.blue,
  });

  @override
  State<AnimatedMicIcon> createState() => _AnimatedMicIconState();
}

class _AnimatedMicIconState extends State<AnimatedMicIcon> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AnimatedMicIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.animateTo(0.0);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: widget.size * 1.5,
            height: widget.size * 1.5,
            decoration: BoxDecoration(
              color: widget.isRecording 
                  ? Colors.red.withOpacity(0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic,
              size: widget.size,
              color: widget.isRecording ? Colors.red : widget.color,
            ),
          ),
        );
      },
    );
  }
}
