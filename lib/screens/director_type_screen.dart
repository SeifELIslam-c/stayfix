import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import 'condo_dashboard_screen.dart';
import 'immeuble_dashboard.dart';
import 'manager_profile_config.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DirectorTypeScreen extends StatefulWidget {
  const DirectorTypeScreen({super.key});

  @override
  State<DirectorTypeScreen> createState() => _DirectorTypeScreenState();
}

class _DirectorTypeScreenState extends State<DirectorTypeScreen> {
  String? _selectedType;
  bool _isLoading = false;

  ManagerProfileOption? get _selectedOption =>
      managerProfileOptionByValue(_selectedType);

  @override
  void initState() {
    super.initState();
    _selectedType = kManagerProfileOptions.first.value;
  }

  Future<void> _saveSelection() async {
    final option = _selectedOption;
    if (option == null || _isLoading) {
      showAuthError(
        context,
        'S\u00e9lectionnez votre profil pour continuer.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showAuthError(
          context,
          'Session introuvable. Veuillez vous reconnecter.',
        );
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'directorType': option.label,
        'propertyProfileType': option.value,
        'propertyProfileLabel': option.label,
        'profileCompletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      final Widget nextScreen = option.value == 'building_manager' ||
              option.value == 'rental_building'
          ? ImmeubleDashboardScreen(propertyType: option.value)
          : CondoDashboardScreen(
              propertyType: option.value,
            );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => nextScreen),
      );
    } catch (_) {
      if (mounted) {
        showAuthError(context, "Erreur lors de l'enregistrement du profil.");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleOptionTap(ManagerProfileOption option) async {
    if (_isLoading) return;
    setState(() => _selectedType = option.value);
    await _saveSelection();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final isCompact = size.height <= 820 || size.width <= 370;
    final heroHeight =
        (size.height * (isCompact ? 0.335 : 0.36)).clamp(230.0, 310.0);
    final panelTop = heroHeight - 26;
    final panelHorizontalPadding = isCompact ? 18.0 : 22.0;
    final innerGap = isCompact ? 8.0 : 10.0;
    final featuredHeight = isCompact ? 98.0 : 108.0;
    final titleSize = isCompact ? 29.0 : 34.0;

    return Scaffold(
      backgroundColor: kAuthBg,
      body: SizedBox(
        height: size.height,
        child: Stack(
          children: [
            _RoleHero(height: heroHeight),
            Positioned(
              top: panelTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: kAuthPanel,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(42),
                    topRight: Radius.circular(42),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 30,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      panelHorizontalPadding,
                      isCompact ? 18 : 22,
                      panelHorizontalPadding,
                      mediaQuery.padding.bottom + (isCompact ? 10 : 14),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text(
                          'Bienvenue',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kAuthGoldDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quel type de bien\ng\u00e9rez-vous ?',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            color: kAuthText,
                            height: 0.92,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'S\u00e9lectionnez votre profil pour personnaliser votre espace de gestion.',
                          style: GoogleFonts.manrope(
                            fontSize: isCompact ? 14 : 15.5,
                            fontWeight: FontWeight.w500,
                            color: kAuthMuted,
                            height: 1.34,
                          ),
                        ),
                        SizedBox(height: isCompact ? 12 : 14),
                        _FeaturedRoleCard(
                          option: kManagerProfileOptions[0],
                          isSelected:
                              _selectedType == kManagerProfileOptions[0].value,
                          onTap: () => _handleOptionTap(
                            kManagerProfileOptions[0],
                          ),
                          height: featuredHeight,
                          compact: isCompact,
                          isLoading: _isLoading,
                        ),
                        SizedBox(height: innerGap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                                    Expanded(
                                      child: _GridRoleCard(
                                        option: kManagerProfileOptions[1],
                                        isSelected: _selectedType ==
                                            kManagerProfileOptions[1].value,
                                        onTap: () => _handleOptionTap(
                                          kManagerProfileOptions[1],
                                        ),
                                        compact: isCompact,
                                        isLoading: _isLoading,
                                      ),
                                    ),
                                    SizedBox(width: innerGap),
                                    Expanded(
                                      child: _GridRoleCard(
                                        option: kManagerProfileOptions[2],
                                        isSelected: _selectedType ==
                                            kManagerProfileOptions[2].value,
                                        onTap: () => _handleOptionTap(
                                          kManagerProfileOptions[2],
                                        ),
                                        compact: isCompact,
                                        isLoading: _isLoading,
                                      ),
                                    ),
                          ],
                        ),
                        SizedBox(height: innerGap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                                    Expanded(
                                      child: _GridRoleCard(
                                        option: kManagerProfileOptions[3],
                                        isSelected: _selectedType ==
                                            kManagerProfileOptions[3].value,
                                        onTap: () => _handleOptionTap(
                                          kManagerProfileOptions[3],
                                        ),
                                        compact: isCompact,
                                        isLoading: _isLoading,
                                      ),
                                    ),
                                    SizedBox(width: innerGap),
                                    Expanded(
                                      child: _GridRoleCard(
                                        option: kManagerProfileOptions[4],
                                        isSelected: _selectedType ==
                                            kManagerProfileOptions[4].value,
                                        onTap: () => _handleOptionTap(
                                          kManagerProfileOptions[4],
                                        ),
                                        compact: isCompact,
                                        isLoading: _isLoading,
                                      ),
                                    ),
                          ],
                        ),
                      ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleHero extends StatelessWidget {
  const _RoleHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/selectionheroimg.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Container(color: kAuthBg),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14000000),
                  Color(0x11000000),
                  Color(0xA3050505),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedRoleCard extends StatelessWidget {
  const _FeaturedRoleCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.height,
    required this.compact,
    required this.isLoading,
  });

  final ManagerProfileOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final double height;
  final bool compact;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _RoleCardShell(
      isSelected: isSelected,
      onTap: onTap,
      enabled: !isLoading,
      borderRadius: 22,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: compact ? 106 : 120,
              child: Center(
                child: _RoleIcon(
                  value: option.value,
                  size: compact ? 64 : 74,
                  featured: true,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: compact ? 18 : 20,
                  bottom: compact ? 18 : 20,
                  right: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cormorantGaramond(
                        color: Colors.white,
                        fontSize: compact ? 20 : 23,
                        fontWeight: FontWeight.w700,
                        height: 0.98,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      option.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: compact ? 12.2 : 13.2,
                        fontWeight: FontWeight.w500,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _ChevronBubble(
                selected: isSelected,
                size: compact ? 42 : 46,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridRoleCard extends StatelessWidget {
  const _GridRoleCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.compact,
    required this.isLoading,
  });

  final ManagerProfileOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final bool compact;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _RoleCardShell(
      isSelected: isSelected,
      onTap: onTap,
      enabled: !isLoading,
      borderRadius: 20,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 12,
          compact ? 10 : 12,
          compact ? 10 : 12,
          compact ? 8 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoleIcon(
                  value: option.value,
                  size: compact ? 36 : 42,
                  featured: false,
                ),
                const Spacer(),
                _ChevronBubble(
                  selected: isSelected,
                  size: compact ? 30 : 34,
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Text(
                    option.label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: compact ? 12.6 : 14.0,
                      fontWeight: FontWeight.w700,
                      height: 1.14,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 6),
                Text(
                  option.subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.72),
                      fontSize: compact ? 10.6 : 11.6,
                      fontWeight: FontWeight.w500,
                      height: 1.24,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleCardShell extends StatelessWidget {
  const _RoleCardShell({
    required this.child,
    required this.isSelected,
    required this.onTap,
    required this.borderRadius,
    required this.enabled,
  });

  final Widget child;
  final bool isSelected;
  final VoidCallback onTap;
  final double borderRadius;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(borderRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 156),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0B0B0B),
                Color(0xFF121212),
              ],
            ),
            border: Border.all(
              color: isSelected ? kAuthGold : const Color(0xFFC99645),
              width: isSelected ? 1.6 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
              if (isSelected)
                BoxShadow(
                  color: kAuthGold.withValues(alpha: 0.22),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChevronBubble extends StatelessWidget {
  const _ChevronBubble({
    required this.selected,
    required this.size,
  });

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? kAuthGold : kAuthGold.withValues(alpha: 0.72),
          width: 1.1,
        ),
        color:
            selected ? kAuthGold.withValues(alpha: 0.12) : Colors.transparent,
      ),
      child: Icon(
        LucideIcons.chevronRight,
        color: kAuthGold,
        size: size * 0.48,
      ),
    );
  }
}

class _RoleIcon extends StatelessWidget {
  const _RoleIcon({
    required this.value,
    required this.size,
    required this.featured,
  });

  final String value;
  final double size;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    switch (value) {
      case 'hotel_manager':
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              LucideIcons.hotel,
              color: kAuthGold,
              size: size,
            ),
            Positioned(
              top: -size * 0.18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  featured ? 5 : 3,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Icon(
                      LucideIcons.star,
                      color: kAuthGold,
                      size: featured ? size * 0.13 : size * 0.12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'building_manager':
        return Icon(
          LucideIcons.building2,
          color: kAuthGold,
          size: size,
        );
      case 'rental_building':
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              LucideIcons.keyRound,
              color: kAuthGold,
              size: size * 0.88,
            ),
            Positioned(
              bottom: size * 0.02,
              right: size * 0.02,
              child: Icon(
                LucideIcons.home,
                color: kAuthGold,
                size: size * 0.34,
              ),
            ),
          ],
        );
      case 'villa_owner':
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              LucideIcons.home,
              color: kAuthGold,
              size: size * 0.92,
            ),
            Positioned(
              top: -size * 0.06,
              right: -size * 0.02,
              child: Icon(
                LucideIcons.trees,
                color: kAuthGold,
                size: size * 0.26,
              ),
            ),
          ],
        );
      default:
        return Icon(
          LucideIcons.building,
          color: kAuthGold,
          size: size * 0.94,
        );
    }
  }
}
