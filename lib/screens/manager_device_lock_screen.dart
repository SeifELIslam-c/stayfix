import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/manager_session_guard.dart';
import '../providers/hotel_provider.dart';
import 'auth_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

const _kLockGold = Color(0xFFD6A85A);
const _kLockGoldDeep = Color(0xFFB8863B);
const _kLockCard = Color(0xFF111111);

class ManagerDeviceLockScreen extends StatefulWidget {
  const ManagerDeviceLockScreen({
    super.key,
    required this.destinationBuilder,
  });

  final Future<Widget> Function() destinationBuilder;

  @override
  State<ManagerDeviceLockScreen> createState() =>
      _ManagerDeviceLockScreenState();
}

class _ManagerDeviceLockScreenState extends State<ManagerDeviceLockScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isUnlocking = false;

  Future<void> _unlock() async {
    if (_isUnlocking) return;
    setState(() => _isUnlocking = true);

    try {
      // Check if the user actually has enrolled biometric credentials.
      bool hasEnrolled = false;
      try {
        final biometrics = await _localAuth.getAvailableBiometrics();
        hasEnrolled = biometrics.isNotEmpty;
      } catch (_) {
        // Cannot query — assume nothing enrolled, unlock directly.
      }

      if (!mounted) return;

      if (hasEnrolled) {
        // Enrolled credentials exist — prompt the user.
        bool authenticated = false;
        try {
          authenticated = await _localAuth.authenticate(
            localizedReason:
                'Déverrouillez StayFix pour retrouver votre session.',
          );
        } on PlatformException {
          // Plugin/OS error — treat as no lock so user is never blocked.
          authenticated = true;
        }

        if (!mounted) return;

        if (!authenticated) {
          // User explicitly dismissed the prompt.
          _showSnack('Déverrouillage annulé');
          return;
        }
      }
      // No enrolled credentials ? bypass auth, unlock directly.

      // Unlock and navigate — account stays remembered on device.
      ManagerSessionGuard.markUnlocked();
      final destination = await widget.destinationBuilder();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destination),
        (_) => false,
      );
    } catch (_) {
      // Last resort — unlock rather than permanently block the user.
      if (mounted) {
        ManagerSessionGuard.markUnlocked();
        final destination = await widget.destinationBuilder();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => destination),
          (_) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  Future<void> _useAnotherAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _kLockCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            'Utiliser un autre compte ?',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: Text(
            'Votre session mémorisée sera fermée sur cet appareil.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Annuler',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kLockGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Continuer',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    ManagerSessionGuard.reset();
    final provider = Provider.of<HotelProvider>(context, listen: false);
    await provider.logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kLockCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/devbackground.webp',
              fit: BoxFit.cover,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.48),
                    Colors.black.withValues(alpha: 0.40),
                    Colors.black.withValues(alpha: 0.74),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
            const Positioned(
              top: -84,
              left: -84,
              child: _GlowRing(size: 250),
            ),
            const Positioned(
              top: 110,
              right: -70,
              child: _GlowRing(size: 190, opacity: 0.18),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _ShieldLockBadge(),
                    const SizedBox(height: 24),
                    _LockMainCard(
                      isUnlocking: _isUnlocking,
                      onUnlock: _unlock,
                      onUseAnotherAccount: _useAnotherAccount,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShieldLockBadge extends StatelessWidget {
  const _ShieldLockBadge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 4,
          child: Container(
            width: 94,
            height: 16,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: _kLockGold.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.black.withValues(alpha: 0.18),
              ],
            ),
            color: _kLockCard.withValues(alpha: 0.88),
            border: Border.all(color: _kLockGold.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            LucideIcons.shieldCheck,
            color: _kLockGold,
            size: 64,
          ),
        ),
      ],
    );
  }
}

class _LockMainCard extends StatelessWidget {
  const _LockMainCard({
    required this.isUnlocking,
    required this.onUnlock,
    required this.onUseAnotherAccount,
  });

  final bool isUnlocking;
  final VoidCallback onUnlock;
  final VoidCallback onUseAnotherAccount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A1A).withValues(alpha: 0.95),
                const Color(0xFF0F0F0F).withValues(alpha: 0.97),
              ],
            ),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: _kLockGold.withValues(alpha: 0.50)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Compte verrouillé',
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 58,
                height: 2,
                decoration: BoxDecoration(
                  color: _kLockGold.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Déverrouillez avec le code, l’empreinte ou Face ID de cet appareil pour retrouver votre session.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.76),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              const _RememberedSessionInfoCard(),
              const SizedBox(height: 28),
              _UnlockButton(
                isUnlocking: isUnlocking,
                onTap: onUnlock,
              ),
              const SizedBox(height: 28),
              const _OrDivider(),
              const SizedBox(height: 18),
              InkWell(
                onTap: onUseAnotherAccount,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Utiliser un autre compte',
                        style: GoogleFonts.inter(
                          color: _kLockGold,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        LucideIcons.chevronRight,
                        color: _kLockGold,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RememberedSessionInfoCard extends StatelessWidget {
  const _RememberedSessionInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kLockGold.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kLockGold.withValues(alpha: 0.20)),
            ),
            child: const Icon(
              LucideIcons.smartphone,
              color: _kLockGold,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Votre compte reste mémorisé sur cet appareil jusqu’à ce que vous vous déconnectiez.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.isUnlocking,
    required this.onTap,
  });

  final bool isUnlocking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _kLockGold.withValues(alpha: 0.42),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isUnlocking ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFF8D98A),
                _kLockGold,
                _kLockGoldDeep,
              ],
            ),
          ),
          child: Container(
            width: double.infinity,
            height: 66,
            alignment: Alignment.center,
            child: isUnlocking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.lock,
                        color: Colors.black,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Déverrouiller',
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'OU',
            style: GoogleFonts.inter(
              color: _kLockGold.withValues(alpha: 0.86),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _GlowRing extends StatelessWidget {
  const _GlowRing({
    required this.size,
    this.opacity = 0.24,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _kLockGold.withValues(alpha: opacity),
          width: 1.4,
        ),
      ),
    );
  }
}
