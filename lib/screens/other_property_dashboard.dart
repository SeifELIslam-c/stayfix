import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/hotel_provider.dart';
import 'auth_screen.dart';
import 'director_type_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class OtherPropertyDashboard extends StatelessWidget {
  const OtherPropertyDashboard({
    super.key,
    required this.propertyType,
  });

  final String propertyType;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final heroHeight =
        (mediaQuery.size.height * 0.34).clamp(250.0, 320.0).toDouble();

    return Scaffold(
      backgroundColor: kAuthBg,
      body: SizedBox.expand(
        child: Stack(
          children: [
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/selectionheroimg.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: kAuthBg),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x26000000),
                          Color(0x33000000),
                          Color(0xC4050505),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      _GlassCircleButton(
                        icon: LucideIcons.arrowLeft,
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DirectorTypeScreen(),
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      _GlassCircleButton(
                        icon: LucideIcons.logOut,
                        onTap: () async {
                          final provider = Provider.of<HotelProvider>(context,
                              listen: false);
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuthScreen(),
                            ),
                            (route) => false,
                          );
                          await provider.logout();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: heroHeight - 34,
              child: Container(
                decoration: const BoxDecoration(
                  color: kAuthPanel,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(42),
                    topRight: Radius.circular(42),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      22,
                      24,
                      22,
                      mediaQuery.padding.bottom + 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'StayFix',
                          style: GoogleFonts.cormorantGaramond(
                            color: kAuthGoldDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Section en maintenance',
                          style: GoogleFonts.cormorantGaramond(
                            color: kAuthText,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 0.96,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Le profil ${propertyType.toLowerCase()} sera bientot disponible dans votre espace StayFix.',
                          style: GoogleFonts.manrope(
                            color: kAuthMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF0B0B0B),
                                Color(0xFF151515),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: kAuthGold.withValues(alpha: 0.7),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 26,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: kAuthGold.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.wrench,
                                  color: kAuthGold,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Fonctionnalite en preparation',
                                style: GoogleFonts.cormorantGaramond(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  height: 0.98,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Nous finalisons ce tableau de bord pour vous offrir une experience premium sans approximation.',
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _LuxuryActionButton(
                          label: 'Choisir un autre profil',
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DirectorTypeScreen(),
                              ),
                            );
                          },
                        ),
                      ],
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

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
            border: Border.all(color: kAuthGold.withValues(alpha: 0.58)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _LuxuryActionButton extends StatelessWidget {
  const _LuxuryActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF090909),
                Color(0xFF171717),
              ],
            ),
            border: Border.all(color: kAuthGold.withValues(alpha: 0.84)),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                margin: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: kAuthGold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.arrowRight,
                  color: Colors.black,
                  size: 22,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: GoogleFonts.cormorantGaramond(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 54),
            ],
          ),
        ),
      ),
    );
  }
}
