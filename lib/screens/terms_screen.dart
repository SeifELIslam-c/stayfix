import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/hotel_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_screen.dart';
import 'manager_navigation.dart';

const Color _termsBg = Color(0xFF050505);
const Color _termsPanel = Color(0xFFFFFDF8);
const Color _termsGold = Color(0xFFD6A85A);
const Color _termsGoldDark = Color(0xFFB8863B);
const Color _termsText = Color(0xFF111111);
const Color _termsMuted = Color(0xFF6B7280);
const Color _termsBorder = Color(0xFFDDD6CC);
const String _termsFrench = '''STAYFIX - CONDITIONS D'UTILISATION

1. Accord aux conditions
En accedant ou en utilisant StayFix ("la Plateforme"), vous acceptez ces conditions d'utilisation. Si vous ne les acceptez pas, vous ne pouvez pas utiliser la Plateforme.

2. Role de la plateforme
StayFix est une plateforme technologique de gestion et d'organisation pour les operations hotelieres et la gestion de proprietes.
- Nous ne garantissons pas de resultats commerciaux ou operationnels
- Nous ne remplacons pas les decisions de gestion
- Nous ne sommes pas responsables des choix internes de votre equipe
Les decisions prises dans votre etablissement restent sous votre responsabilite.

3. Comptes utilisateur
Les utilisateurs doivent :
- Fournir des informations exactes, completes et verifiables
- Maintenir la confidentialite de leurs identifiants
- Etre responsables des activites realisees avec leur compte
Nous pouvons suspendre ou fermer un compte en cas d'abus, fraude ou usage non autorise.

4. Utilisation acceptable
Les utilisateurs acceptent de ne pas :
- Falsifier leur identite ou les informations de l'etablissement
- Utiliser la plateforme a des fins illegales, trompeuses ou abusives
- Perturber les services, l'infrastructure ou la securite de la plateforme
- Tenter d'acceder a des donnees sans autorisation

5. Donnees et confidentialite
Certaines donnees saisies dans StayFix peuvent etre stockees et traitees pour faire fonctionner les services. Nous traitons ces donnees conformement aux lois applicables en matiere de protection des donnees. Nous ne vendons pas les donnees personnelles.

6. Disponibilite du service
Nous faisons de notre mieux pour maintenir StayFix accessible et fiable, mais nous ne garantissons pas un fonctionnement ininterrompu ni sans erreur.

7. Propriete intellectuelle
Tous les contenus, elements graphiques, marques et logiciels de StayFix restent la propriete de StayFix ou de ses partenaires. Vous ne pouvez pas les copier, redistribuer ou modifier sans autorisation.

8. Limitation de responsabilite
Dans les limites autorisees par la loi :
- StayFix n'est pas responsable des dommages indirects, accessoires ou consecutifs
- L'utilisation de la plateforme se fait a vos risques
- Nous ne sommes pas responsables des pertes liees a des erreurs de saisie, de configuration ou de gestion interne

9. Modifications
Nous pouvons mettre a jour ces conditions a tout moment. L'utilisation continue de la plateforme constitue une acceptation des conditions revisees.

10. Droit applicable
Ces conditions sont regies par les lois applicables dans la juridiction ou StayFix opere, sauf disposition legale contraire.''';

const String _termsEnglish = '''STAYFIX - TERMS OF USE

1. Agreement to Terms
By accessing or using StayFix ("the Platform"), you agree to these Terms of Use. If you do not agree, you may not use the Platform.

2. Platform Role
StayFix is a technology platform for hospitality operations and property management.
- We do not guarantee business or operational outcomes
- We do not replace management decisions
- We are not responsible for your team's internal choices
All operational decisions remain under your control.

3. User Accounts
Users must:
- Provide accurate, complete, and verifiable information
- Keep login credentials confidential
- Be responsible for all activity under their account
We may suspend or terminate accounts in cases of abuse, fraud, or unauthorized use.

4. Acceptable Use
Users agree not to:
- Misrepresent their identity or property information
- Use the platform for illegal, deceptive, or abusive purposes
- Disrupt services, infrastructure, or platform security
- Attempt to access data without authorization

5. Data and Privacy
Certain data entered into StayFix may be stored and processed to operate the service. We handle data in accordance with applicable privacy laws. We do not sell personal data.

6. Service Availability
We strive to keep StayFix accessible and reliable, but we do not guarantee uninterrupted or error-free service.

7. Intellectual Property
All content, visuals, trademarks, and software within StayFix remain the property of StayFix or its partners. You may not copy, distribute, or modify them without authorization.

8. Limitation of Liability
To the maximum extent permitted by law:
- StayFix is not liable for indirect, incidental, or consequential damages
- Use of the platform is at your own risk
- We are not responsible for losses caused by data entry mistakes, configuration issues, or internal management decisions

9. Changes
We may update these Terms at any time. Continued use of the platform constitutes acceptance of the revised Terms.

10. Governing Law
These Terms are governed by applicable laws in the jurisdiction where StayFix operates, unless otherwise required by law.''';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key, this.isFirstTime = true});

  final bool isFirstTime;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isFrench = true;
  bool _hasScrolledToEnd = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atEnd = position.pixels >= position.maxScrollExtent - 12;
    if (atEnd != _hasScrolledToEnd && mounted) {
      setState(() => _hasScrolledToEnd = atEnd);
    }
  }

  Future<void> _handleAccept() async {
    if (_isLoading || !_hasScrolledToEnd) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'termsAccepted': true,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
          'termsAcceptedLanguage': _isFrench ? 'fr' : 'en',
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      final nextScreen = await resolveManagerDestination();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => nextScreen),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAuthError(context, 'Erreur: $e');
    }
  }

  Future<void> _handleDecline() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await Provider.of<HotelProvider>(context, listen: false).logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userId');

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAuthError(context, 'Erreur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final heroHeight = (size.height * 0.34).clamp(250.0, 320.0);
    final termsText = _isFrench ? _termsFrench : _termsEnglish;
    final declineLabel = _isFrench ? 'Refuser' : 'Decline';
    final acceptLabel = _isFrench ? 'Accepter' : 'Accept';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      body: Stack(
        children: [
          Column(
            children: [
              _TermsHero(height: heroHeight),
              const Expanded(
                child: ColoredBox(color: Color(0xFFF7F3EC)),
              ),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: heroHeight - 24),
                      ),
                      SliverToBoxAdapter(
                        child: Transform.translate(
                          offset: const Offset(0, -28),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: _termsPanel,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(34),
                                topRight: Radius.circular(34),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 30,
                                  offset: Offset(0, -8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 16, 20, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _LanguageChip(
                                        label: 'FR',
                                        isActive: _isFrench,
                                        onTap: () =>
                                            setState(() => _isFrench = true),
                                      ),
                                      const SizedBox(width: 10),
                                      _LanguageChip(
                                        label: 'EN',
                                        isActive: !_isFrench,
                                        onTap: () =>
                                            setState(() => _isFrench = false),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _isFrench ? 'Conditions' : 'Terms',
                                    style: GoogleFonts.cormorantGaramond(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      color: _termsText,
                                      height: 0.95,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _isFrench
                                        ? 'Lisez et acceptez les conditions pour continuer sur StayFix.'
                                        : 'Read and accept the terms to continue on StayFix.',
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: _termsMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: _termsBorder),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          LucideIcons.scrollText,
                                          color: _termsGoldDark,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _hasScrolledToEnd
                                                ? (_isFrench
                                                    ? 'Lecture complete. Vous pouvez maintenant accepter.'
                                                    : 'Reading complete. You can now accept.')
                                                : (_isFrench
                                                    ? 'Faites defiler jusqu en bas pour activer le bouton Accepter.'
                                                    : 'Scroll to the bottom to enable the Accept button.'),
                                            style: GoogleFonts.manrope(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _termsText,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      18,
                                      18,
                                      24,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: _termsBorder),
                                    ),
                                    child: Text(
                                      termsText,
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _termsText,
                                        height: 1.65,
                                      ),
                                    ),
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
                Container(
                  color: _termsPanel,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    mediaQuery.padding.bottom + 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TermsSecondaryButton(
                          label: declineLabel,
                          onTap: _isLoading ? null : _handleDecline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TermsPrimaryButton(
                          label: acceptLabel,
                          enabled: _hasScrolledToEnd && !_isLoading,
                          isLoading: _isLoading,
                          onTap: _handleAccept,
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

class _TermsHero extends StatelessWidget {
  const _TermsHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/termsheroimg.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Container(color: _termsBg),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14000000),
                  Color(0x22000000),
                  Color(0xB2050505),
                ],
              ),
            ),
          ),
          Positioned(
            top: topPadding + 16,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.88),
                  child: InkWell(
                    onTap: () => Navigator.maybePop(context),
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        LucideIcons.arrowLeft,
                        color: _termsText,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'StayFix',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _termsGold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Conditions d utilisation',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 0.94,
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

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? _termsGold : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? _termsGold : _termsBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.black : _termsText,
          ),
        ),
      ),
    );
  }
}

class _TermsPrimaryButton extends StatelessWidget {
  const _TermsPrimaryButton({
    required this.label,
    required this.enabled,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF0B0B0B),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: enabled ? _termsGold : _termsBorder,
            ),
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : _termsMuted,
                  ),
                ),
        ),
      ),
    );
  }
}

class _TermsSecondaryButton extends StatelessWidget {
  const _TermsSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _termsBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: _termsText,
            ),
          ),
        ),
      ),
    );
  }
}
