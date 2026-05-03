// lib/features/admin/presentation/widgets/status_badge.dart
// Widget _StatusBadge corrigé pour accepter un String? nullable.
// Remplacez l'appel dans admin_page.dart :
//   _StatusBadge(status: user.status)          ← fonctionne désormais
// car le widget accepte String? et gère la valeur nulle.

import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  /// [status] peut être null (utilisateur sans statut défini).
  final String? status;

  const StatusBadge({super.key, this.status});

  @override
  Widget build(BuildContext context) {
    final label = _label(status);
    final color = _color(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'Nunito',
        ),
      ),
    );
  }

  static String _label(String? status) {
    switch (status) {
      case 'active':
        return 'Actif';
      case 'inactive':
        return 'Inactif';
      case 'suspended':
        return 'Suspendu';
      case 'pending':
        return 'En attente';
      default:
        return status ?? 'Inconnu';
    }
  }

  static Color _color(String? status) {
    switch (status) {
      case 'active':
        return const Color(0xFF22C55E);
      case 'inactive':
        return const Color(0xFF94A3B8);
      case 'suspended':
        return const Color(0xFFEF4444);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}

// ── PATCH pour admin_page.dart ─────────────────────────────────
// Remplacez dans admin_page.dart la ligne 270 :
//   _StatusBadge(status: user.status),          // ← ERREUR : String? != String
// Par :
//   StatusBadge(status: user.status),           // ← OK (accepte String?)
//
// Et l'ancienne classe _StatusBadge interne par un import de ce fichier :
//   import '../widgets/status_badge.dart';