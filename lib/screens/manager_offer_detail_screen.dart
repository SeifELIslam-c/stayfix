import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import 'manager_chat_thread_screen.dart';
import '../services/manager_worker_contact_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ManagerOfferDetailScreen extends StatelessWidget {
  const ManagerOfferDetailScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.workerDepartment,
    required this.workerDisplayLabel,
    required this.title,
    required this.description,
    required this.category,
    this.photoBase64,
    this.photoUrl,
    this.price,
    this.originalRate,
    this.targetCity,
    this.targetRegion,
    this.isAvailable = false,
  });

  final String workerId;
  final String workerName;
  final String workerDepartment;
  final String workerDisplayLabel;
  final String title;
  final String description;
  final String category;
  final String? photoBase64;
  final String? photoUrl;
  final double? price;
  final double? originalRate;
  final String? targetCity;
  final String? targetRegion;
  final bool isAvailable;

  Future<void> _openConversation(BuildContext context) async {
    final handle = await ManagerWorkerContactService.openConversation(
      workerId: workerId,
      workerName: workerName,
      workerDepartment: workerDepartment,
      sendSelectionMessage: false,
    );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManagerChatThreadScreen(
          conversationId: handle.conversationId,
          title: handle.title,
          subtitle: handle.subtitle,
          avatarBase64: handle.avatarBase64,
          avatarUrl: handle.avatarUrl,
          isAvailable: handle.isAvailable,
          initialBannerText: handle.openingBanner,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(photoBase64!);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: kAuthBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            backgroundColor: kAuthBg,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (photoUrl != null && photoUrl!.isNotEmpty)
                    Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _OfferFallback(
                        bytes: bytes,
                        workerName: workerName,
                      ),
                    )
                  else
                    _OfferFallback(bytes: bytes, workerName: workerName),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x22000000),
                          Color(0x8A000000),
                          kAuthBg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workerName,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      workerDisplayLabel.isNotEmpty
                          ? workerDisplayLabel
                          : (workerDepartment.isNotEmpty
                              ? workerDepartment
                              : category),
                      style: GoogleFonts.inter(
                        color: kAuthGold,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChipInfo(
                          icon: LucideIcons.tag,
                          label: price == null
                              ? 'Tarif sur demande'
                              : '${price!.toStringAsFixed(0)} DZD / h',
                        ),
                        if (originalRate != null)
                          _ChipInfo(
                            icon: LucideIcons.tag,
                            label: 'Avant ${originalRate!.toStringAsFixed(0)}',
                          ),
                        _ChipInfo(
                          icon: LucideIcons.mapPin,
                          label: [targetCity ?? '', targetRegion ?? '']
                                  .where((e) => e.isNotEmpty)
                                  .join(', ')
                                  .isEmpty
                              ? 'Zone non precisee'
                              : [targetCity ?? '', targetRegion ?? '']
                                  .where((e) => e.isNotEmpty)
                                  .join(', '),
                        ),
                        _ChipInfo(
                          icon: LucideIcons.circle,
                          label: isAvailable ? 'Disponible' : 'Indisponible',
                          color: isAvailable
                              ? const Color(0xFF22C55E)
                              : Colors.white70,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _InfoPanel(
                      title: 'Titre de l offre',
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoPanel(
                      title: 'Description complete',
                      child: Text(
                        description.trim().isEmpty
                            ? 'Aucune description supplementaire.'
                            : description.trim(),
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoPanel(
                      title: 'Categorie',
                      child: Text(
                        workerDisplayLabel.isNotEmpty
                            ? workerDisplayLabel
                            : category,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openConversation(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAuthGold,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(LucideIcons.messageCircle),
                        label: Text(
                          'Contacter cet intervenant',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferFallback extends StatelessWidget {
  const _OfferFallback({
    required this.bytes,
    required this.workerName,
  });

  final Uint8List? bytes;
  final String workerName;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFF151515),
      alignment: Alignment.center,
      child: Text(
        workerName.isEmpty ? '?' : workerName[0].toUpperCase(),
        style: GoogleFonts.cormorantGaramond(
          color: kAuthGold,
          fontSize: 90,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33D6A85A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: kAuthGold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: resolvedColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
