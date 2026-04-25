import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  final bool showOnline;

  const AvatarWidget({
    super.key,
    required this.name,
    this.size = 44,
    this.imageUrl,
    this.showOnline = false,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Color _colorFromName() {
    final colors = [
      AppColors.primary,
      const Color(0xFF0F5232),
      const Color(0xFF2EA05E),
      const Color(0xFF0D7A4E),
      const Color(0xFF1A6B3C),
    ];
    int hash = 0;
    for (var char in name.codeUnits) {
      hash = (hash + char) % colors.length;
    }
    return colors[hash];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _colorFromName(),
            shape: BoxShape.circle,
          ),
          child: imageUrl != null
              ? ClipOval(
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildInitials(),
                  ),
                )
              : _buildInitials(),
        ),
        if (showOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          fontFamily: 'Nunito',
        ),
      ),
    );
  }
}