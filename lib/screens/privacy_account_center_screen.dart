import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/hotel_provider.dart';
import 'auth_screen.dart';
import '../services/app_env.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _legalBg = Color(0xFF070707);
const _legalCard = Color(0xFF111111);
const _legalBorder = Color(0x33D6A85A);
const _legalDanger = Color(0xFFB42318);

const List<String> _deleteAccountReasons = <String>[
  'Je n utilise plus Stayfix',
  'Je souhaite proteger mes donnees',
  'Je cree un autre compte',
  'Je ne trouve plus ce dont j ai besoin',
  'Autre raison',
];

Future<void> showDeleteAccountFlow(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const DeleteAccountScreen(),
    ),
  );
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  String _selectedReason = _deleteAccountReasons.first;
  bool _isSubmitting = false;

  HotelProvider get _provider =>
      Provider.of<HotelProvider>(context, listen: false);

  bool get _requiresPassword =>
      _provider.currentAuthProviders.contains('password');
  bool get _usesGoogleAuth =>
      _provider.currentAuthProviders.contains('google.com');
  bool get _usesAppleAuth =>
      _provider.currentAuthProviders.contains('apple.com');
  bool get _usesSocialReauth =>
      !_requiresPassword && (_usesGoogleAuth || _usesAppleAuth);
  String get _socialProviderLabel => _usesAppleAuth ? 'Apple' : 'Google';

  bool get _canSubmit {
    final confirmed = _confirmationController.text.trim().toUpperCase() ==
        'DELETE';
    final hasPassword = !_requiresPassword ||
        _passwordController.text.trim().isNotEmpty;
    return confirmed && hasPassword && !_isSubmitting;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _pickReason() async {
    final currentIndex = _deleteAccountReasons.indexOf(_selectedReason);
    final initialIndex = currentIndex < 0 ? 0 : currentIndex;
    var tempIndex = initialIndex;
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) {
        return Container(
          height: 340,
          padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF101010),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(popupContext).pop(),
                      child: const Text('Annuler'),
                    ),
                    Text(
                      'Motif',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(popupContext)
                          .pop(_deleteAccountReasons[tempIndex]),
                      child: const Text('Valider'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 48,
                  diameterRatio: 1.12,
                  useMagnifier: true,
                  magnification: 1.05,
                  backgroundColor: const Color(0xFF101010),
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex,
                  ),
                  onSelectedItemChanged: (index) => tempIndex = index,
                  selectionOverlay: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x33D6A85A)),
                      color: const Color(0x10D6A85A),
                    ),
                  ),
                  children: _deleteAccountReasons
                      .map(
                        (reason) => Center(
                          child: Text(
                            reason,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _selectedReason = selected);
    }
  }

  Future<void> _submitDeletion() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

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

    final result = await _provider.deleteCurrentAccount(
      currentPassword: _passwordController.text.trim().isEmpty
          ? null
          : _passwordController.text.trim(),
    );
    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (!result.success) {
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
      return;
    }

    debugPrint('Stayfix delete account reason selected: $_selectedReason');
    await _showDeletionSuccessDialog();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _showDeletionSuccessDialog() async {
    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    if (isApple) {
      await showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return CupertinoAlertDialog(
            title: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0x1FD6A85A),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: Color(0xFFD6A85A),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Compte supprime',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            content: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Votre compte Stayfix et les donnees associees ont ete supprimes. Vous allez maintenant revenir a la connexion.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continuer'),
              ),
            ],
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _legalCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0x33D6A85A), Color(0x11D6A85A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    LucideIcons.badgeCheck,
                    color: Color(0xFFD6A85A),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Compte supprime',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Votre compte Stayfix et les donnees associees ont ete supprimes. Vous allez maintenant revenir a la connexion.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD6A85A),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      'Continuer',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _legalBg,
      appBar: AppBar(
        backgroundColor: _legalBg,
        foregroundColor: Colors.white,
        title: Text(
          'Supprimer le compte',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _legalCard,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _legalBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0x1FB42318),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    LucideIcons.alertTriangle,
                    color: Color(0xFFFF8B8D),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Supprimer definitivement votre compte Stayfix',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Cette action supprimera votre acces et les documents utilisateur associes a votre compte. Elle est irreversible.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _LegalSection(
            title: 'Avant de continuer',
            icon: LucideIcons.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PolicyBullet(
                  text:
                      'Votre connexion actuelle sera fermee sur cet appareil apres confirmation.',
                ),
                _PolicyBullet(
                  text:
                      'Les informations de profil liees a votre compte seront supprimees.',
                ),
                _PolicyBullet(
                  text:
                      'Vous pourrez recreer un compte plus tard, mais cette suppression n est pas annulable.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LegalSection(
            title: 'Motif de suppression',
            icon: LucideIcons.clipboardList,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choisissez la raison principale pour laquelle vous quittez Stayfix.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _isSubmitting ? null : _pickReason,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _legalBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedReason,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          LucideIcons.chevronDown,
                          color: Color(0xFFD6A85A),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LegalSection(
            title: 'Confirmation',
            icon: LucideIcons.lock,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_requiresPassword) ...[
                  _DialogInput(
                    controller: _passwordController,
                    label: 'Mot de passe actuel',
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_usesSocialReauth) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _legalBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.shieldCheck,
                          color: Color(0xFFD6A85A),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'En continuant, Stayfix rouvrira $_socialProviderLabel pour vous demander de choisir a nouveau votre compte avant la suppression.',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.82),
                              height: 1.45,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _DialogInput(
                  controller: _confirmationController,
                  label: 'Tapez DELETE pour confirmer',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pour des raisons de securite, nous vous demandons une confirmation explicite avant la suppression.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canSubmit ? _submitDeletion : null,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.trash2, size: 18),
              label: Text(
                _isSubmitting
                    ? 'Suppression en cours...'
                    : _usesSocialReauth
                        ? 'Continuer avec $_socialProviderLabel'
                        : 'Supprimer definitivement mon compte',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _legalDanger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _legalDanger.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                'Annuler',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final supportUrl = await AppEnv.get(
      'STAYFIX_SUPPORT_URL',
      fallback: 'https://stayfix-accountdeletion.netlify.app/support/',
    );
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
          'Confidentialite et compte',
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
                title: '1. Donn\u00e9es collect\u00e9es',
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
                title: 'Suppression du compte',
                icon: LucideIcons.trash2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vous pouvez lancer une suppression definitive depuis cet espace. Une page de confirmation vous demandera votre motif et une validation explicite.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LegalButton(
                      label: 'Ouvrir la suppression du compte',
                      icon: LucideIcons.arrowRight,
                      onTap: () => showDeleteAccountFlow(context),
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
