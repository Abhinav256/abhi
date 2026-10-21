import 'package:flutter/material.dart';

class SwipeToConfirm extends StatefulWidget {
  final String text;
  final VoidCallback onConfirm;
  final bool isLoading;

  const SwipeToConfirm({
    super.key,
    required this.text,
    required this.onConfirm,
    this.isLoading = false,
  });

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> with SingleTickerProviderStateMixin {
  double _position = 0.0;
  bool _isConfirmed = false;
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _animController.addListener(() {
      setState(() {
        _position = _animation.value;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading && !widget.isLoading && _isConfirmed) {
      // Reset if it was loading but now it's not (e.g. error happened)
      setState(() {
        _isConfirmed = false;
        _position = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        const double height = 54.0;
        const double handleSize = height - 8;
        final double maxPosition = maxWidth - handleSize - 8;

        return Container(
          width: maxWidth,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1B6BB8), Color(0xFF0F4F94)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D145DA0),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background Text
              Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Opacity(
                        opacity: _isConfirmed ? 0.0 : (1.0 - (_position / maxPosition)).clamp(0.0, 1.0),
                        child: Text(
                          widget.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              // Swipe Handle
              if (!widget.isLoading)
                Positioned(
                  left: _position + 4,
                  top: 4,
                  child: GestureDetector(
                    onPanStart: (details) {
                      _animController.stop();
                    },
                    onPanUpdate: (details) {
                      if (_isConfirmed) return;
                      setState(() {
                        _position += details.delta.dx;
                        if (_position < 0) _position = 0;
                        if (_position > maxPosition) _position = maxPosition;
                      });
                    },
                    onPanEnd: (details) {
                      if (_isConfirmed) return;
                      if (_position > maxPosition * 0.75) {
                        _animation = Tween<double>(begin: _position, end: maxPosition).animate(
                          CurvedAnimation(parent: _animController, curve: Curves.easeOut),
                        );
                        _animController.forward(from: 0.0).then((_) {
                          setState(() {
                            _isConfirmed = true;
                          });
                          widget.onConfirm();
                        });
                      } else {
                        _animation = Tween<double>(begin: _position, end: 0.0).animate(
                          CurvedAnimation(parent: _animController, curve: Curves.easeOut),
                        );
                        _animController.forward(from: 0.0);
                      }
                    },
                    child: Container(
                      width: handleSize,
                      height: handleSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.double_arrow,
                        color: Color(0xFF0F4F94),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
