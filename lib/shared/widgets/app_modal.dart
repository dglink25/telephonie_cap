import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

enum ModalType { success, error, warning, info, call }


class AppModal {
  // ── Show ──────────────────────────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    required ModalType type,
    required String title,
    required String message,
    String buttonText = 'OK',
    VoidCallback? onClose,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppModalDialog(
        type: type,
        title: title,
        message: message,
        buttonText: buttonText,
        onClose: onClose,
      ),
    );
  }

  static Future<void> success(
    BuildContext context, {
    required String title,
    String message = '',
    VoidCallback? onClose,
  }) =>
      show(context,
          type: ModalType.success,
          title: title,
          message: message,
          onClose: onClose);

  static Future<void> error(
    BuildContext context, {
    required String title,
    String message = '',
    VoidCallback? onClose,
  }) =>
      show(context,
          type: ModalType.error,
          title: title,
          message: message,
          onClose: onClose);

  static Future<void> warning(
    BuildContext context, {
    required String title,
    String message = '',
    VoidCallback? onClose,
  }) =>
      show(context,
          type: ModalType.warning,
          title: title,
          message: message,
          onClose: onClose);

  static Future<void> info(
    BuildContext context, {
    required String title,
    String message = '',
    VoidCallback? onClose,
  }) =>
      show(context,
          type: ModalType.info,
          title: title,
          message: message,
          onClose: onClose);
}

class _AppModalDialog extends StatefulWidget {
  final ModalType type;
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback? onClose;

  const _AppModalDialog({
    required this.type,
    required this.title,
    required this.message,
    required this.buttonText,
    this.onClose,
  });

  @override
  State<_AppModalDialog> createState() => _AppModalDialogState();
}

class _AppModalDialogState extends State<_AppModalDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = Tween<double>(begin: 0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  _ModalConfig get _config => _configFor(widget.type);

  void _close() {
    Navigator.of(context).pop();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;

    return FadeTransition(
      opacity: _fade,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header coloré ──────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: cfg.gradientColors,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Icône animée
                      _AnimatedIcon(icon: cfg.icon, color: Colors.white),
                      const SizedBox(height: 14),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Corps ──────────────────────────────────────
                if (widget.message.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.grey600,
                        fontSize: 14,
                        height: 1.6,
                        fontFamily: 'Nunito',
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),

                // ── Bouton OK ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _close,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cfg.buttonColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        widget.buttonText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _ModalConfig _configFor(ModalType type) {
    switch (type) {
      case ModalType.success:
        return _ModalConfig(
          icon: Icons.check_circle_rounded,
          gradientColors: [const Color(0xFF1B7F4A), const Color(0xFF2EA05E)],
          buttonColor: const Color(0xFF1B7F4A),
        );
      case ModalType.error:
        return _ModalConfig(
          icon: Icons.error_rounded,
          gradientColors: [const Color(0xFFDC2626), const Color(0xFFEF4444)],
          buttonColor: const Color(0xFFDC2626),
        );
      case ModalType.warning:
        return _ModalConfig(
          icon: Icons.warning_rounded,
          gradientColors: [const Color(0xFFD97706), const Color(0xFFF59E0B)],
          buttonColor: const Color(0xFFD97706),
        );
      case ModalType.info:
        return _ModalConfig(
          icon: Icons.info_rounded,
          gradientColors: [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)],
          buttonColor: const Color(0xFF1D4ED8),
        );
      case ModalType.call:
        return _ModalConfig(
          icon: Icons.call_rounded,
          gradientColors: [const Color(0xFF0F5232), const Color(0xFF1B7F4A)],
          buttonColor: const Color(0xFF1B7F4A),
        );
    }
  }
}

class _ModalConfig {
  final IconData icon;
  final List<Color> gradientColors;
  final Color buttonColor;

  const _ModalConfig({
    required this.icon,
    required this.gradientColors,
    required this.buttonColor,
  });
}

class _AnimatedIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _AnimatedIcon({required this.icon, required this.color});

  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
        ),
        child: Icon(widget.icon, color: widget.color, size: 36),
      ),
    );
  }
}