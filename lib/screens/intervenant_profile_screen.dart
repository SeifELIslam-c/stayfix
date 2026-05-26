// ignore_for_file: unused_element

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/screens/manager_chat_thread_screen.dart';
import 'package:hotel_lux_os/screens/manager_notifications_screen.dart';
import 'package:hotel_lux_os/services/manager_worker_contact_service.dart';
import 'package:hotel_lux_os/services/vps_media_service.dart';
import 'package:hotel_lux_os/widgets/unread_messages_nav_item.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hotel_lux_os/providers/hotel_provider.dart';

// ── Local constants ────────────────────────────────────────────────────────────
const _kProfBg = Color(0xFF070707);
const _kProfCard = Color(0xFF111111);
const _kProfGoldBorder = Color(0x44D6A85A);
const _kProfGreen = Color(0xFF22C55E);
const _kOrangeDot = Color(0xFFFF6B35);

// ═══════════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════════

class _WorkerAvatarFallback extends StatelessWidget {
  const _WorkerAvatarFallback({
    required this.initials,
  });

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kAuthGold.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: kAuthGold,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class IntervenantProfileScreen extends StatefulWidget {
  const IntervenantProfileScreen({super.key, required this.workerId});

  final String workerId;

  @override
  State<IntervenantProfileScreen> createState() =>
      _IntervenantProfileScreenState();
}

class _IntervenantProfileScreenState extends State<IntervenantProfileScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  final Map<String, bool> _sectionExpanded = <String, bool>{
    'availability': false,
    'personal': false,
    'professional': false,
    'languages': false,
    'verifications': false,
  };

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(widget.workerId)
          .get();
      if (!mounted) return;
      setState(() {
        _data = doc.data();
        _isLoading = false;
        _error = doc.exists ? null : 'Profil introuvable';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Impossible de charger le profil';
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kProfCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  void _handleChoose() {
    final name = (_data?['username'] as String?)?.trim() ?? 'cet intervenant';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kProfCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Passer en StayUp avec cet intervenant ?',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: Text(
          name,
          style: GoogleFonts.inter(
            color: kAuthGold,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAuthGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _showSnack('Intervenant passe en StayUp');
            },
            child: Text(
              'Confirmer',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _handleContact() {
    final phone = (_data?['phone'] as String?)?.trim();
    final email = (_data?['email'] as String?)?.trim();
    if ((phone == null || phone.isEmpty) && (email == null || email.isEmpty)) {
      _showSnack('Coordonnées non renseignées');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(phone: phone, email: email),
    );
  }

  Future<void> _handleChooseChat() async {
    await _openWorkerConversation(sendSelectionMessage: true);
  }

  Future<void> _handleContactChat() async {
    final phone = (_data?['phone'] as String?)?.trim();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManagerWorkerContactSheet(
        phone: phone,
        onMessageTap: () async {
          Navigator.pop(context);
          await _openWorkerConversation(sendSelectionMessage: false);
        },
        onCallTap: _hasCallablePhone(phone)
            ? () async {
                Navigator.pop(context);
                await _launchDialer(phone!);
              }
            : null,
      ),
    );
  }

  Future<void> _showQuickActionsMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionsSheet(
        onMessagesTap: () async {
          Navigator.pop(context);
          await _openWorkerConversation(sendSelectionMessage: false);
        },
        onNotificationsTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ManagerNotificationsScreen(),
            ),
          );
        },
        onContactTap: () async {
          Navigator.pop(context);
          await _handleContactChat();
        },
        onLogoutTap: () async {
          Navigator.pop(context);
          await _handleLogout();
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _kProfCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Se deconnecter ?',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'Vous devrez vous reconnecter pour acceder a votre espace.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.inter(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAuthGold,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Deconnexion',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed != true || !mounted) return;
    await Provider.of<HotelProvider>(context, listen: false).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _openWorkerConversation({
    required bool sendSelectionMessage,
  }) async {
    final data = _data;
    if (data == null) return;

    try {
      final handle = await ManagerWorkerContactService.openConversation(
        workerId: widget.workerId,
        workerName: (data['username'] as String?)?.trim(),
        workerRole: (data['role'] as String?)?.trim(),
        workerDepartment: (data['department'] as String?)?.trim(),
        workerPhotoBase64: (data['photoBase64'] as String?)?.trim(),
        isWorkerAvailable: _isWorkerAvailableNow(data),
        workerPhone: (data['phone'] as String?)?.trim(),
        sendSelectionMessage: sendSelectionMessage,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ManagerChatThreadScreen(
            conversationId: handle.conversationId,
            title: handle.title,
            subtitle: handle.subtitle,
            avatarUrl: handle.avatarUrl,
            avatarBase64: handle.avatarBase64,
            isAvailable: handle.isAvailable,
            initialBannerText: handle.openingBanner,
          ),
        ),
      );
    } on WorkerBlockedException {
      if (!mounted) return;
      final shouldUnblock = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: _kProfCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Intervenant bloque',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Text(
                'Vous avez bloque cet intervenant. Voulez-vous le debloquer ?',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Annuler',
                    style: GoogleFonts.inter(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAuthGold,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Debloquer'),
                ),
              ],
            ),
          ) ??
          false;
      if (!shouldUnblock) return;
      await ManagerWorkerContactService.unblockWorker(
          workerId: widget.workerId);
      if (!mounted) return;
      _showSnack('Intervenant debloque.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d ouvrir cette conversation pour le moment.');
    }
  }

  Future<void> _launchDialer(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    _showSnack('Impossible d ouvrir le composeur telephonique.');
  }

  bool _hasCallablePhone(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return false;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 6;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kProfBg,
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: kAuthGold, strokeWidth: 2))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.userX,
              color: Colors.white.withValues(alpha: 0.35), size: 48),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _kProfCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kProfGoldBorder),
              ),
              child: Text(
                'Retour',
                style: GoogleFonts.inter(
                    color: kAuthGold, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final data = _data!;
    final name = ((data['username'] as String?)?.trim()) ?? 'Non renseigné';
    final department = ((data['department'] as String?)?.trim()) ?? '';
    final directSpecialty = ((data['specialty'] as String?)?.trim()) ??
        ((data['speciality'] as String?)?.trim()) ??
        '';
    final specialties = _parseStringList(data['specialties']);
    final primarySpecialty = _resolvePrimarySpecialty(
      directSpecialty: directSpecialty,
      specialties: specialties,
    );
    final displayRole = _resolveWorkerHeadlineLabel(
      department: department,
      primarySpecialty: primarySpecialty,
    );
    final displayRoleHint = _resolveWorkerHeadlineHint(
      department: department,
      primarySpecialty: primarySpecialty,
    );
    final showSpecialtiesSection =
        specialties.isNotEmpty && !_isQualifiedLaborDepartment(department);
    final expYears = (data['departmentExperienceYears'] as num?)?.toInt();
    final address = ((data['address'] as String?)?.trim()) ?? '';
    final isAvailable = _isWorkerAvailableNow(data);
    final photoBase64 = (data['photoBase64'] as String?)?.trim();
    final photoUrl = VpsMediaService.resolveProfileImageUrl(data);
    final photoBytes = _decodeBase64(photoBase64);
    final initials = _workerInitials(name);

    // Availability slots
    final Map<String, dynamic> slotData = data;
    final availSlots = _parseAvailabilitySlots(slotData);

    // Languages
    final speaksFrench = data['speaksFrench'] as bool? ?? false;
    final speaksEnglish = data['speaksEnglish'] as bool? ?? false;

    // CV
    final cvBase64 = (data['cvBase64'] as String?)?.trim();
    final cvBytes = _decodeBase64(cvBase64);
    final cvFileNameRaw = (data['cvFileName'] as String?)?.trim() ?? '';
    final cvFileName = cvFileNameRaw.isNotEmpty ? cvFileNameRaw : 'CV.pdf';
    final cvReviewAuth = data['cvReviewAuthorization'] as bool? ?? false;

    // Questionnaire
    final questionnaire = data['cvQuestionnaire'];
    final Map<String, dynamic> quest = questionnaire is Map
        ? Map<String, dynamic>.from(questionnaire)
        : const {};
    final rating = (data['rating'] as num?)?.toDouble();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ProfileHeroSection(
            name: name,
            headlineLabel: displayRole,
            headlineHint: displayRoleHint,
            address: address,
            expYears: expYears,
            rating: rating,
            photoUrl: photoUrl,
            photoBytes: photoBytes,
            initials: initials,
            onBack: () => Navigator.pop(context),
            onChat: () => _openWorkerConversation(sendSelectionMessage: false),
            onMenu: _showQuickActionsMenu,
            onBell: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManagerNotificationsScreen(),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _PrimaryBtn(onTap: _handleChooseChat),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SecondaryBtn(onTap: _handleContactChat),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AvailabilityBadge(isAvailable: isAvailable),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        // Availability card — shown first
        SliverToBoxAdapter(
          child: _AvailabilityCard(
            slots: availSlots,
            isExpanded: _sectionExpanded['availability'] ?? true,
            onToggle: () => setState(() {
              _sectionExpanded['availability'] =
                  !(_sectionExpanded['availability'] ?? true);
            }),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // Personal info card
        SliverToBoxAdapter(
          child: _SectionCard(
            isExpanded: _sectionExpanded['personal'] ?? false,
            onToggle: () => setState(() {
              _sectionExpanded['personal'] =
                  !(_sectionExpanded['personal'] ?? false);
            }),
            icon: LucideIcons.user,
            title: 'Informations personnelles',
            rows: [
              _InfoRow(label: 'Nom complet', value: name),
              _InfoRow(
                  label: 'Email', value: (data['email'] as String?)?.trim()),
              _InfoRow(
                  label: 'Téléphone',
                  value: (data['phone'] as String?)?.trim()),
              _InfoRow(
                  label: 'Adresse', value: address.isNotEmpty ? address : null),
              _InfoRow(
                  label: 'Date de naissance',
                  value: (data['dob'] as String?)?.trim(),
                  isLast: true),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // Professional profile card
        SliverToBoxAdapter(
          child: _SectionCard(
            isExpanded: _sectionExpanded['professional'] ?? true,
            onToggle: () => setState(() {
              _sectionExpanded['professional'] =
                  !(_sectionExpanded['professional'] ?? true);
            }),
            icon: LucideIcons.briefcase,
            title: 'Profil professionnel',
            rows: [
              _InfoRow(
                label: _isQualifiedLaborDepartment(department)
                    ? 'Spécialité'
                    : 'Département',
                value: displayRole.isNotEmpty ? displayRole : null,
              ),
              if (expYears != null)
                _InfoRow(
                    label: 'Expérience',
                    value: '$expYears an${expYears > 1 ? "s" : ""}'),
              _InfoRow(
                  label: 'Poste actuel',
                  value: (data['jobLocation'] as String?)?.trim()),
              _InfoRow(
                  label: 'Lieu de travail',
                  value: (data['jobAddress'] as String?)?.trim()),
              _InfoRow(
                  label: 'Date de début',
                  value: (data['jobStartDate'] as String?)?.trim(),
                  isLast: !showSpecialtiesSection),
            ],
            extraChild: showSpecialtiesSection
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spécialités',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: specialties
                              .map((s) => _SpecialtyChip(label: s))
                              .toList(),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // Languages card
        SliverToBoxAdapter(
          child: _LanguagesCard(
            speaksFrench: speaksFrench,
            speaksEnglish: speaksEnglish,
            isExpanded: _sectionExpanded['languages'] ?? true,
            onToggle: () => setState(() {
              _sectionExpanded['languages'] =
                  !(_sectionExpanded['languages'] ?? true);
            }),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // Verifications card
        SliverToBoxAdapter(
          child: _VerificationsCard(
            cvReviewAuth: cvReviewAuth,
            quest: quest,
            isExpanded: _sectionExpanded['verifications'] ?? true,
            onToggle: () => setState(() {
              _sectionExpanded['verifications'] =
                  !(_sectionExpanded['verifications'] ?? true);
            }),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // CV card
        SliverToBoxAdapter(
          child: _CvCard(
            cvBytes: cvBytes,
            cvFileName: cvFileName,
            cvReviewAuth: cvReviewAuth,
            onFullScreen: cvBytes != null
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PdfFullScreenPage(
                          pdfBytes: cvBytes,
                          fileName: cvFileName,
                        ),
                      ),
                    )
                : null,
            onDownload: () => _showSnack('Téléchargement bientôt disponible.'),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Hero section
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfileHeroSection extends StatelessWidget {
  const _ProfileHeroSection({
    required this.name,
    required this.headlineLabel,
    required this.headlineHint,
    required this.address,
    required this.expYears,
    required this.rating,
    required this.photoUrl,
    required this.photoBytes,
    required this.initials,
    required this.onBack,
    required this.onChat,
    required this.onMenu,
    required this.onBell,
  });

  final String name;
  final String headlineLabel;
  final String headlineHint;
  final String address;
  final int? expYears;
  final double? rating;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final String initials;
  final VoidCallback onBack;
  final VoidCallback onChat;
  final VoidCallback onMenu;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 290,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/interventfilterheroimg.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF0A0A0A)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.45, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0.33),
                  Colors.black.withValues(alpha: 0.13),
                  Colors.black.withValues(alpha: 0.93),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      _CircleBtn(icon: LucideIcons.arrowLeft, onTap: onBack),
                      const Spacer(),
                      Text(
                        'Profil intervenant',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CircleBtn(icon: LucideIcons.menu, onTap: onMenu),
                          const SizedBox(width: 10),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _CircleBtn(icon: LucideIcons.bell, onTap: onBell),
                              const Positioned(
                                top: 5,
                                right: 5,
                                child: UnreadMessagesDot(
                                  size: 9,
                                  color: _kOrangeDot,
                                  borderColor: Color(0xFF070707),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Avatar + info row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Avatar
                      Stack(
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E1E1E),
                              border: Border.all(color: kAuthGold, width: 2),
                            ),
                            child: ClipOval(
                              child: photoUrl != null && photoUrl!.isNotEmpty
                                  ? Image.network(
                                      photoUrl!,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) =>
                                          photoBytes != null
                                              ? Image.memory(
                                                  photoBytes!,
                                                  fit: BoxFit.cover,
                                                  filterQuality:
                                                      FilterQuality.high,
                                                )
                                              : _WorkerAvatarFallback(
                                                  initials: initials,
                                                ),
                                    )
                                  : photoBytes != null
                                      ? Image.memory(
                                          photoBytes!,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.high,
                                        )
                                      : _WorkerAvatarFallback(
                                          initials: initials,
                                        ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            if (headlineLabel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                headlineHint,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                headlineLabel,
                                style: GoogleFonts.inter(
                                  color: kAuthGold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ],
                            if (rating != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: kAuthGold.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      LucideIcons.star,
                                      color: kAuthGold,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      rating!.toStringAsFixed(1),
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (address.isNotEmpty) ...[
                                  const Icon(
                                    LucideIcons.mapPin,
                                    color: kAuthGold,
                                    size: 11,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: Colors.white
                                            .withValues(alpha: 0.60),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                if (address.isNotEmpty && expYears != null)
                                  const SizedBox(width: 10),
                                if (expYears != null) ...[
                                  const Icon(
                                    LucideIcons.calendarDays,
                                    color: kAuthGold,
                                    size: 11,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$expYears an${expYears! > 1 ? "s" : ""}',
                                    style: GoogleFonts.inter(
                                      color:
                                          Colors.white.withValues(alpha: 0.60),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Action buttons
// ═══════════════════════════════════════════════════════════════════════════════

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kAuthGoldDark, kAuthGold],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.userPlus, size: 18, color: Colors.black),
            const SizedBox(width: 10),
            Text(
              'StayUp avec cet intervenant',
              style: GoogleFonts.inter(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: _kProfCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.phone, size: 18, color: kAuthGold),
            const SizedBox(width: 10),
            Text(
              'Contacter',
              style: GoogleFonts.inter(
                color: kAuthGold,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section card
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.rows,
    required this.isExpanded,
    required this.onToggle,
    this.extraChild,
  });

  final IconData icon;
  final String title;
  final List<_InfoRow> rows;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? extraChild;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.where((row) => row.shouldDisplay).toList();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kProfCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kProfGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(icon, color: kAuthGold, size: 16),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    LucideIcons.chevronUp,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 1,
                thickness: 1),
            const SizedBox(height: 8),
            if (visibleRows.isEmpty && extraChild == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Aucune information selectionnee.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
              )
            else ...[
              ...visibleRows,
              if (extraChild != null) extraChild!,
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String? value;
  final bool isLast;

  bool get shouldDisplay => value?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  (value?.isNotEmpty == true) ? value! : 'Non renseigné',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    color: (value?.isNotEmpty == true)
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              thickness: 1),
      ],
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  const _SpecialtyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kAuthGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAuthGold.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: kAuthGold,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Availability card
// ═══════════════════════════════════════════════════════════════════════════════

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.slots,
    required this.isExpanded,
    required this.onToggle,
  });
  final List<String> slots;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kProfCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kProfGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(LucideIcons.clock, color: kAuthGold, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Disponibilités',
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    LucideIcons.chevronUp,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 1,
                thickness: 1),
            const SizedBox(height: 10),
            if (slots.isEmpty)
              const _EmptyState(label: 'Disponibilités non renseignées')
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: slots.map((slot) {
                  final isAlways = slot.toLowerCase().contains('toujours') ||
                      slot.toLowerCase().contains('tous les jours');
                  return _AvailPill(label: slot, isGreen: isAlways);
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }
}

class _AvailPill extends StatelessWidget {
  const _AvailPill({required this.label, required this.isGreen});
  final String label;
  final bool isGreen;

  @override
  Widget build(BuildContext context) {
    final color = isGreen ? _kProfGreen : kAuthGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGreen) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: _kProfGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Languages card
// ═══════════════════════════════════════════════════════════════════════════════

class _LanguagesCard extends StatelessWidget {
  const _LanguagesCard({
    required this.speaksFrench,
    required this.speaksEnglish,
    required this.isExpanded,
    required this.onToggle,
  });
  final bool speaksFrench;
  final bool speaksEnglish;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final hasAny = speaksFrench || speaksEnglish;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kProfCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kProfGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(LucideIcons.languages, color: kAuthGold, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Langues',
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    LucideIcons.chevronUp,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 1,
                thickness: 1),
            const SizedBox(height: 8),
            if (!hasAny)
              const _EmptyState(label: 'Langues non renseignées')
            else ...[
              if (speaksFrench)
                _LangRow(language: 'Français', isLast: !speaksEnglish),
              if (speaksEnglish)
                const _LangRow(language: 'Anglais', isLast: true),
            ],
          ],
        ],
      ),
    );
  }
}

class _LangRow extends StatelessWidget {
  const _LangRow({required this.language, required this.isLast});
  final String language;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Text(
                language,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              const Icon(LucideIcons.checkCircle2,
                  color: _kProfGreen, size: 18),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              thickness: 1),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Verifications card
// ═══════════════════════════════════════════════════════════════════════════════

class _VerificationsCard extends StatelessWidget {
  const _VerificationsCard({
    required this.cvReviewAuth,
    required this.quest,
    required this.isExpanded,
    required this.onToggle,
  });
  final bool cvReviewAuth;
  final Map<String, dynamic> quest;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final authorizedCanada = quest['authorizedToWorkCanada'] as bool?;
    final isAdult = quest['isAdult'] as bool?;
    final noCriminal = quest['noCriminalRecord'] as bool?;
    final referred = quest['referredByEmployee'] as bool?;
    final referralId = (quest['referralEmployeeId'] as String?)?.trim();

    // Build only the rows the worker actually filled in.
    // cvReviewAuth is always shown (it's a required bool field).
    final showReferralId =
        referred == true && referralId != null && referralId.isNotEmpty;
    final rows = <Widget>[
      if (authorizedCanada != null)
        _VerifRow(
          label: 'Autorisé à travailler au Canada',
          value: authorizedCanada,
        ),
      if (isAdult != null)
        _VerifRow(label: 'Majeur (18 ans et plus)', value: isAdult),
      if (noCriminal != null)
        _VerifRow(label: 'Aucun casier judiciaire', value: noCriminal),
      if (referred != null)
        _VerifRow(label: 'Référé par un employé', value: referred),
      _VerifRow(
        label: 'Autorisation de révision CV',
        value: cvReviewAuth,
        isLast: !showReferralId,
      ),
      if (showReferralId)
        _VerifRow(label: 'ID du référent', valueText: referralId, isLast: true),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kProfCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kProfGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck, color: kAuthGold, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Vérifications',
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    LucideIcons.chevronUp,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 1,
                thickness: 1),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const _EmptyState(label: 'Aucune vérification renseignée.')
            else
              ...rows,
          ],
        ],
      ),
    );
  }
}

class _VerifRow extends StatelessWidget {
  const _VerifRow({
    required this.label,
    this.value,
    this.valueText,
    this.isLast = false,
  });

  final String label;
  final bool? value;
  final String? valueText;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    Widget trailing;
    if (valueText != null) {
      trailing = Text(
        valueText!,
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.70),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      );
    } else if (value == null) {
      trailing = Text(
        '—',
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.30),
          fontSize: 13,
        ),
      );
    } else if (value!) {
      trailing =
          const Icon(LucideIcons.checkCircle2, color: _kProfGreen, size: 18);
    } else {
      trailing = Icon(LucideIcons.circle,
          color: kAuthGold.withValues(alpha: 0.60), size: 18);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
        if (!isLast)
          Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              thickness: 1),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CV card
// ═══════════════════════════════════════════════════════════════════════════════

class _CvCard extends StatelessWidget {
  const _CvCard({
    required this.cvBytes,
    required this.cvFileName,
    required this.cvReviewAuth,
    required this.onFullScreen,
    required this.onDownload,
  });

  final Uint8List? cvBytes;
  final String cvFileName;
  final bool cvReviewAuth;
  final VoidCallback? onFullScreen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kProfCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kProfGoldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(LucideIcons.fileText, color: kAuthGold, size: 16),
              const SizedBox(width: 8),
              Text(
                'CV du candidat',
                style: GoogleFonts.inter(
                  color: kAuthGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cvFileName,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.60),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _OutlineButton(
                  label: 'Plein écran',
                  icon: LucideIcons.maximize2,
                  onTap: onFullScreen ?? () {},
                  enabled: onFullScreen != null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GoldButton(
                  label: 'Télécharger',
                  icon: LucideIcons.download,
                  onTap: onDownload,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // PDF preview or state
          if (!cvReviewAuth)
            _CvWarningState()
          else if (cvBytes != null)
            _PdfInlinePreview(pdfBytes: cvBytes!)
          else
            const _EmptyState(label: 'Aucun CV disponible'),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? kAuthGold.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? kAuthGold : Colors.white.withValues(alpha: 0.30),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.inter(
                color:
                    enabled ? kAuthGold : Colors.white.withValues(alpha: 0.30),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kAuthGoldDark, kAuthGold]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: Colors.black),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CvWarningState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Le candidat n\'a pas autorisé la révision de son CV.',
              style: GoogleFonts.inter(
                color: Colors.orange.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfInlinePreview extends StatefulWidget {
  const _PdfInlinePreview({required this.pdfBytes});
  final Uint8List pdfBytes;

  @override
  State<_PdfInlinePreview> createState() => _PdfInlinePreviewState();
}

class _PdfInlinePreviewState extends State<_PdfInlinePreview> {
  final PdfViewerController _controller = PdfViewerController();
  int _currentPage = 1;
  int _pageCount = 1;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFF0E0E0E),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Page $_currentPage / $_pageCount',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _pageCount > 1
                            ? 'Glissez vers le bas pour voir la suite'
                            : 'Document sur une seule page',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _pageCount <= 0 ? 0 : _currentPage / _pageCount,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(kAuthGold),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 480,
              child: SfPdfViewer.memory(
                widget.pdfBytes,
                controller: _controller,
                enableDoubleTapZooming: true,
                enableTextSelection: true,
                pageLayoutMode: PdfPageLayoutMode.single,
                scrollDirection: PdfScrollDirection.vertical,
                onDocumentLoaded: (details) {
                  if (!mounted) return;
                  setState(() {
                    _pageCount = details.document.pages.count;
                    _currentPage = 1;
                  });
                },
                onPageChanged: (details) {
                  if (!mounted) return;
                  setState(() {
                    _currentPage = details.newPageNumber;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full screen PDF page
// ═══════════════════════════════════════════════════════════════════════════════

class _PdfFullScreenPage extends StatelessWidget {
  const _PdfFullScreenPage({required this.pdfBytes, required this.fileName});
  final Uint8List pdfBytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          fileName,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(LucideIcons.maximize2,
                color: Colors.white.withValues(alpha: 0.55), size: 18),
          ),
        ],
      ),
      body: SfPdfViewer.memory(
        pdfBytes,
        enableDoubleTapZooming: true,
        enableTextSelection: true,
        pageLayoutMode: PdfPageLayoutMode.continuous,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Contact bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({this.phone, this.email});
  final String? phone;
  final String? email;

  void _copy(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          '$label copié',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Contacter',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          if (phone != null && phone!.isNotEmpty)
            _ContactRow(
              icon: LucideIcons.phone,
              label: 'Téléphone',
              value: phone!,
              onTap: () => _copy(context, phone!, 'Téléphone'),
            ),
          if (phone != null &&
              phone!.isNotEmpty &&
              email != null &&
              email!.isNotEmpty)
            const SizedBox(height: 10),
          if (email != null && email!.isNotEmpty)
            _ContactRow(
              icon: LucideIcons.mail,
              label: 'Email',
              value: email!,
              onTap: () => _copy(context, email!, 'Email'),
            ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                'Fermer',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerWorkerContactSheet extends StatelessWidget {
  const _ManagerWorkerContactSheet({
    this.phone,
    required this.onMessageTap,
    this.onCallTap,
  });

  final String? phone;
  final Future<void> Function() onMessageTap;
  final Future<void> Function()? onCallTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Contacter',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _ContactActionTile(
            icon: LucideIcons.messageCircle,
            title: 'Envoyer un message',
            subtitle: 'Ouvrir la conversation avec cet intervenant',
            onTap: onMessageTap,
          ),
          if (onCallTap != null) const SizedBox(height: 10),
          if (onCallTap != null)
            _ContactActionTile(
              icon: LucideIcons.phoneCall,
              title: 'Appeler',
              subtitle: 'Ouvrir le composeur telephonique',
              onTap: onCallTap!,
            ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                'Fermer',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsSheet extends StatelessWidget {
  const _QuickActionsSheet({
    required this.onMessagesTap,
    required this.onNotificationsTap,
    required this.onContactTap,
    required this.onLogoutTap,
  });

  final Future<void> Function() onMessagesTap;
  final VoidCallback onNotificationsTap;
  final Future<void> Function() onContactTap;
  final Future<void> Function() onLogoutTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Raccourcis',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _ContactActionTile(
            icon: LucideIcons.messageCircle,
            title: 'Messages',
            subtitle: 'Ouvrir la conversation avec cet intervenant',
            onTap: onMessagesTap,
          ),
          const SizedBox(height: 10),
          _ContactActionTile(
            icon: LucideIcons.bell,
            title: 'Notifications',
            subtitle: 'Voir les notifications du manager',
            onTap: () async => onNotificationsTap(),
          ),
          const SizedBox(height: 10),
          _ContactActionTile(
            icon: LucideIcons.phoneCall,
            title: 'Contacter',
            subtitle: 'Afficher les actions de contact rapides',
            onTap: onContactTap,
          ),
          const SizedBox(height: 10),
          _ContactActionTile(
            icon: LucideIcons.logOut,
            title: 'Deconnexion',
            subtitle: 'Quitter la session et revenir a la connexion',
            onTap: onLogoutTap,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                'Fermer',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactActionTile extends StatelessWidget {
  const _ContactActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kAuthGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: kAuthGold, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.32),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: kAuthGold, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.copy,
              color: Colors.white.withValues(alpha: 0.35),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Small shared widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.isAvailable});
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final color = isAvailable ? _kProfGreen : Colors.grey;
    final label = isAvailable ? 'Disponible' : 'Non disponible';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Local helpers (duplicated to avoid circular import)
// ═══════════════════════════════════════════════════════════════════════════════

Uint8List? _decodeBase64(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) return null;
  try {
    final normalized = rawValue.contains(',')
        ? rawValue.split(',').last.trim()
        : rawValue.trim();
    return base64Decode(normalized);
  } catch (_) {
    return null;
  }
}

String _workerInitials(String name) {
  final parts =
      name.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'I';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

List<String> _parseStringList(dynamic raw) {
  if (raw is List) {
    return raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
  }
  return const [];
}

bool _isQualifiedLaborDepartment(String department) {
  final normalized = department
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('maindoeuvrequalifie');
}

String _resolvePrimarySpecialty({
  required String directSpecialty,
  required List<String> specialties,
}) {
  if (directSpecialty.trim().isNotEmpty) return directSpecialty.trim();
  if (specialties.isNotEmpty) return specialties.first.trim();
  return '';
}

String _resolveWorkerHeadlineLabel({
  required String department,
  required String primarySpecialty,
}) {
  if (_isQualifiedLaborDepartment(department) &&
      primarySpecialty.trim().isNotEmpty) {
    return primarySpecialty.trim();
  }
  return department.trim();
}

String _resolveWorkerHeadlineHint({
  required String department,
  required String primarySpecialty,
}) {
  if (_isQualifiedLaborDepartment(department) &&
      primarySpecialty.trim().isNotEmpty) {
    return 'SPECIALITE METIER';
  }
  return 'DEPARTEMENT D\'INTERVENTION';
}

bool _isWorkerAvailableNow(
  Map<String, dynamic> data, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final slots = data['availabilitySlots'];
  if (slots is List && slots.isNotEmpty) {
    final normalizedSlots = slots.whereType<Map>().toList();
    if (normalizedSlots.isNotEmpty) {
      return normalizedSlots.any((slot) => _isSlotActiveNow(slot, current));
    }
  }
  return data['isAvailable'] == true || data['availableNow'] == true;
}

bool _isSlotActiveNow(Map slot, DateTime now) {
  final weekday = (slot['weekday'] as num?)?.toInt();
  if (weekday == null || weekday < 1 || weekday > 7) return false;
  if (_isAlwaysAvailableSlot(slot)) {
    return now.weekday == weekday;
  }

  final fromMinutes = _slotMinutes(
    hour: (slot['fromHour'] as num?)?.toInt(),
    minute: (slot['fromMinute'] as num?)?.toInt(),
    period: slot['fromPeriod']?.toString(),
  );
  final toMinutes = _slotMinutes(
    hour: (slot['toHour'] as num?)?.toInt(),
    minute: (slot['toMinute'] as num?)?.toInt(),
    period: slot['toPeriod']?.toString(),
  );
  if (fromMinutes == null || toMinutes == null) return false;

  final currentMinutes = now.hour * 60 + now.minute;
  if (fromMinutes == toMinutes) {
    return now.weekday == weekday;
  }

  if (fromMinutes < toMinutes) {
    return now.weekday == weekday &&
        currentMinutes >= fromMinutes &&
        currentMinutes < toMinutes;
  }

  final nextWeekday = weekday == 7 ? 1 : weekday + 1;
  return (now.weekday == weekday && currentMinutes >= fromMinutes) ||
      (now.weekday == nextWeekday && currentMinutes < toMinutes);
}

List<String> _parseAvailabilitySlots(Map<String, dynamic> data) {
  final slots = data['availabilitySlots'];
  if (slots is! List || slots.isEmpty) return const [];
  final normalized = slots.whereType<Map>().toList();
  if (normalized.isEmpty) return const [];

  final allWeekAlways = normalized.length >= 7 &&
      normalized.every(_isAlwaysAvailableSlot) &&
      normalized
              .map((s) => (s['weekday'] as num?)?.toInt())
              .whereType<int>()
              .toSet()
              .length >=
          7;
  if (allWeekAlways) return const ['Tous les jours • Toujours disponible'];

  final result = <String>[];
  for (final slot in normalized) {
    final dayLabel = _weekdayLabel((slot['weekday'] as num?)?.toInt());
    if (_isAlwaysAvailableSlot(slot)) {
      result.add(dayLabel.isNotEmpty
          ? '$dayLabel • Toujours disponible'
          : 'Toujours disponible');
      continue;
    }
    final from = _formatTime(
      hour: (slot['fromHour'] as num?)?.toInt(),
      minute: (slot['fromMinute'] as num?)?.toInt(),
      period: slot['fromPeriod']?.toString(),
    );
    final to = _formatTime(
      hour: (slot['toHour'] as num?)?.toInt(),
      minute: (slot['toMinute'] as num?)?.toInt(),
      period: slot['toPeriod']?.toString(),
    );
    if (from != null && to != null) {
      result
          .add(dayLabel.isNotEmpty ? '$dayLabel • $from - $to' : '$from - $to');
      continue;
    }
    final existing = (slot['label']?.toString() ?? '').trim();
    if (existing.isNotEmpty) {
      result.add(
          dayLabel.isNotEmpty && !existing.toLowerCase().startsWith(dayLabel)
              ? '$dayLabel • $existing'
              : existing);
    }
  }
  return result;
}

String _weekdayLabel(int? weekday) {
  const days = ['', 'lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
  if (weekday == null || weekday < 1 || weekday > 7) return '';
  return days[weekday];
}

bool _isAlwaysAvailableSlot(Map slot) {
  if (slot['allDay'] == true) return true;
  final label = (slot['label']?.toString() ?? '').toLowerCase();
  return label.contains('toujours disponible') ||
      label.contains('toute la journee');
}

int? _slotMinutes(
    {required int? hour, required int? minute, required String? period}) {
  if (hour == null) return null;
  final min = (minute ?? 0).clamp(0, 59);
  final p = (period ?? '').trim().toUpperCase();
  if (p == 'AM' || p == 'PM') {
    var normalizedHour = hour % 12;
    if (p == 'PM') normalizedHour += 12;
    return normalizedHour * 60 + min;
  }
  if (hour < 0 || hour > 23) return null;
  return hour * 60 + min;
}

String? _formatTime(
    {required int? hour, required int? minute, required String? period}) {
  if (hour == null) return null;
  final min = (minute ?? 0).clamp(0, 59);
  final p = (period ?? '').trim().toUpperCase();
  if (p == 'AM' || p == 'PM') {
    return '$hour:${min.toString().padLeft(2, '0')}${p.toLowerCase()}';
  }
  if (hour < 0 || hour > 23) return null;
  final suffix = hour >= 12 ? 'pm' : 'am';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${min.toString().padLeft(2, '0')}$suffix';
}
