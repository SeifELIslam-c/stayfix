import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_os/providers/hotel_provider.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/services/app_env.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _legalBg = Color(0xFF070707);
const _legalCard = Color(0xFF111111);
const _legalBorder = Color(0x33D6A85A);

Future<void> showDeleteAccountFlow(BuildContext context) async {
  final provider = Provider.of<HotelProvider>(context, listen: false);
  final requiresPassword = provider.currentAuthProviders.contains('password');
  final passwordController = TextEditingController();
  final confirmation = TextEditingController();
  bool confirming = false;

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              final isValid = confirmation.text.trim().toUpperCase() ==
                      'DELETE' &&
                  (!requiresPassword || passwordController.text.trim().isNotEmpty) &&
                  !confirming;
              return AlertDialog(
                backgroundColor: _legalCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                title: Text(
                  'Supprimer le compte',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cette action supprimera votre compte Auth et vos documents Firestore utilisateur. Elle est irreversible.',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.78),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (requiresPassword) ...[
                        _DialogInput(
                          controller: passwordController,
                          label: 'Mot de passe actuel',
                          obscureText: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _DialogInput(
                        controller: confirmation,
                        label: 'Tapez DELETE pour confirmer',
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: confirming
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: Text(
                      'Annuler',
                      style: GoogleFonts.inter(color: Colors.white70),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: isValid
                        ? () {
                            setState(() => confirming = true);
                            Navigator.pop(dialogContext, true);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB42318),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Supprimer',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ) ??
      false;

  final password = passwordController.text.trim();
  passwordController.dispose();
  confirmation.dispose();
  if (!confirmed || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Suppression du compte en cours...',
        style: GoogleFonts.inter(color: Colors.white),
      ),
      backgroundColor: _legalCard,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );

  final result = await provider.deleteCurrentAccount(
    currentPassword: password.isEmpty ? null : password,
  );
  if (!context.mounted) return;

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.message,
        style: GoogleFonts.inter(color: Colors.white),
      ),
      backgroundColor: _legalCard,
      behavior: SnackBarBehavior.floating,
    ),
  );

  if (!result.success) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthScreen()),
    (_) => false,
  );
}

class PrivacyAccountCenterScreen extends StatefulWidget {
  const PrivacyAccountCenterScreen({super.key});

  @override
  State<PrivacyAccountCenterScreen> createState() =>
      _PrivacyAccountCenterScreenState();
}

class _PrivacyAccountCenterScreenState
    extends State<PrivacyAccountCenterScreen> {
  late final Future<_SupportLinks> _supportFuture = _loadSupportLinks();

  Future<_SupportLinks> _loadSupportLinks() async {
    final supportUrl = await AppEnv.get('STAYFIX_SUPPORT_URL');
    final supportEmail = await AppEnv.get(
      'STAYFIX_SUPPORT_EMAIL',
      fallback: 'support@stayfix.app',
    );
    return _SupportLinks(
      supportUrl: supportUrl.trim(),
      supportEmail: supportEmail.trim(),
    );
  }

  Future<void> _openUri(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      _showSnack('Lien indisponible.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('Impossible d ouvrir ce lien.');
    }
  }

  Future<void> _composeSupportEmail(String email) async {
    await _openUri(
      'mailto:$email?subject=${Uri.encodeComponent('StayFix support')}',
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: _legalCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: _legalBg,
      appBar: AppBar(
        backgroundColor: _legalBg,
        foregroundColor: Colors.white,
        title: Text(
          'Politique de confidentialite',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<_SupportLinks>(
        future: _supportFuture,
        builder: (context, snapshot) {
          final support = snapshot.data ?? const _SupportLinks.empty();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _LegalSection(
                title: 'Compte connecte',
                icon: LucideIcons.user,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(
                      label: 'Email',
                      value: authUser?.email?.trim().isNotEmpty == true
                          ? authUser!.email!
                          : 'Non disponible',
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(
                      label: 'Connexion',
                      value: _providerSummary(
                        Provider.of<HotelProvider>(context, listen: false)
                            .currentAuthProviders,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: '1. Donnees collectées',
                icon: LucideIcons.shieldCheck,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PolicyBullet(
                      text:
                          'Informations de compte: email, nom, role, telephone, statut d acceptation des termes.',
                    ),
                    _PolicyBullet(
                      text:
                          'Informations professionnelles et de propriete: hotel, immeuble, appartement, affectations, conversations et missions.',
                    ),
                    _PolicyBullet(
                      text:
                          'Medias et messagerie: photos de profil, images, messages vocaux, contenus de conversation et pieces jointes.',
                    ),
                    _PolicyBullet(
                      text:
                          'Donnees techniques limitees: fournisseurs de connexion, dates de creation, preferences de notification et de securite.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: '2. Utilisation des donnees',
                icon: LucideIcons.settings,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PolicyBullet(
                      text:
                          'Fournir l authentification, gerer les roles et donner acces aux espaces hotel, immeuble ou appartement appropries.',
                    ),
                    _PolicyBullet(
                      text:
                          'Permettre la messagerie interne, l attribution de missions, le partage d adresse et la coordination des equipes.',
                    ),
                    _PolicyBullet(
                      text:
                          'Envoyer les emails operationnels lies a la creation de compte et aux notifications de service.',
                    ),
                    _PolicyBullet(
                      text:
                          'Ameliorer la securite locale de l app, comme la biometrie et les alertes de session lorsqu elles sont activees.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: '3. Permissions et acces sensibles',
                icon: LucideIcons.info,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PermissionLine(
                      title: 'Localisation',
                      subtitle:
                          'Recherche d agents proches et selection d adresse dans les flux qui l exigent.',
                    ),
                    _PermissionLine(
                      title: 'Camera et galerie',
                      subtitle:
                          'Photo de profil et partage d images dans les conversations.',
                    ),
                    _PermissionLine(
                      title: 'Microphone',
                      subtitle: 'Enregistrement et envoi de messages vocaux.',
                    ),
                    _PermissionLine(
                      title: 'Biometrie',
                      subtitle:
                          'Deverrouillage local de la session sur l appareil de l utilisateur.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: '4. Stockage, partage et conservation',
                icon: LucideIcons.database,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PolicyBullet(
                      text:
                          'Les donnees sont principalement stockees dans Firebase et dans les services media/configures par StayFix pour les fichiers de conversation.',
                    ),
                    _PolicyBullet(
                      text:
                          'Les donnees sont partagees seulement avec les services necessaires au fonctionnement du produit, comme l authentification, la base de donnees, le stockage media et l envoi d emails operationnels.',
                    ),
                    _PolicyBullet(
                      text:
                          'StayFix ne vend pas les donnees personnelles des utilisateurs.',
                    ),
                    _PolicyBullet(
                      text:
                          'Certaines donnees operationnelles deja rattachees a une mission, une conversation ou une propriete peuvent rester conservees lorsqu elles sont necessaires a la continuite du service, a la securite ou a des obligations legales.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: '5. Vos droits',
                icon: LucideIcons.badgeCheck,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PolicyBullet(
                      text:
                          'Vous pouvez modifier certaines informations de profil directement depuis les ecrans de profil.',
                    ),
                    _PolicyBullet(
                      text:
                          'Vous pouvez demander de l aide ou signaler un comportement abusif via les ecrans de support et de chat.',
                    ),
                    _PolicyBullet(
                      text:
                          'Vous pouvez supprimer votre compte depuis les reglages. Cette suppression vise le compte Auth et les documents Firestore utilisateur associes.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _LegalSection(
                title: 'Support et contact',
                icon: LucideIcons.mail,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(
                      label: 'Support',
                      value: support.supportEmail.isEmpty
                          ? 'support@stayfix.app'
                          : support.supportEmail,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _LegalButton(
                          label: 'Contacter le support',
                          icon: LucideIcons.send,
                          onTap: () => _composeSupportEmail(
                            support.supportEmail.isEmpty
                                ? 'support@stayfix.app'
                                : support.supportEmail,
                          ),
                        ),
                        if (support.supportUrl.isNotEmpty)
                          _LegalButton(
                            label: 'Centre support',
                            icon: LucideIcons.arrowRight,
                            onTap: () => _openUri(support.supportUrl),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _providerSummary(Set<String> providers) {
    if (providers.contains('apple.com')) return 'Apple';
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('password')) return 'Email et mot de passe';
    return 'Session StayFix';
  }
}

class _SupportLinks {
  const _SupportLinks({
    required this.supportUrl,
    required this.supportEmail,
  });

  const _SupportLinks.empty()
      : supportUrl = '',
        supportEmail = '';

  final String supportUrl;
  final String supportEmail;
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _legalCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _legalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFD6A85A), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LegalButton extends StatelessWidget {
  const _LegalButton({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFD6A85A),
        side: const BorderSide(color: Color(0x66D6A85A)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.82),
          height: 1.45,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _PolicyBullet extends StatelessWidget {
  const _PolicyBullet({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(
              LucideIcons.circle,
              color: Color(0xFFD6A85A),
              size: 10,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.82),
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$title: ',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: subtitle),
          ],
        ),
      ),
    );
  }
}

class _DialogInput extends StatelessWidget {
  const _DialogInput({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF171717),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _legalBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _legalBorder),
        ),
      ),
    );
  }
}
