import 'dart:ui';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/hotel_models.dart';
import '../providers/hotel_provider.dart';
import 'dashboard_screen.dart';
import 'manager_navigation.dart';
import '../services/app_session_service.dart';
import 'terms_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

const kAuthBg = Color(0xFF050505);
const kAuthPanel = Color(0xFFFFFDF8);
const kAuthGold = Color(0xFFD6A85A);
const kAuthGoldDark = Color(0xFFB8863B);
const kAuthText = Color(0xFF111111);
const kAuthMuted = Color(0xFF6B7280);
const kAuthBorder = Color(0xFFDDD6CC);
const kAuthDivider = Color(0xFFE7E0D6);

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.mode = AuthMode.login,
  });

  final AuthMode mode;

  bool get isLogin => mode == AuthMode.login;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = true;
  bool _hasSavedUser = false;
  Country _selectedCountry = Country(
    phoneCode: '1',
    countryCode: 'CA',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'Canada',
    example: '2042345678',
    displayName: 'Canada',
    displayNameNoCountryCode: 'Canada',
    e164Key: '',
    fullExampleWithPlusSign: '+12042345678',
  );

  bool get _isLogin => widget.isLogin;
  bool get _supportsAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isLoginFormValid =>
      _emailCtrl.text.trim().isNotEmpty && _passwordCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isLogin) {
      _checkSavedUser();
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSavedUser() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final provider = Provider.of<HotelProvider>(context, listen: false);
    if (provider.currentUser != null) {
      setState(() => _hasSavedUser = true);
      _authenticateWithBiometrics();
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    bool authenticated = false;
    try {
      setState(() => _isLoading = true);
      final bool canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (canAuth) {
        authenticated = await _localAuth.authenticate(
          localizedReason: 'Veuillez vous authentifier pour acceder a StayFix',
        );
      } else {
        authenticated = true;
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (authenticated) {
      _navigateToNextScreen();
    } else {
      showAuthError(context, 'Authentification annulee ou echouee');
    }
  }

  Future<void> _handleLogin() async {
    if (!_isLoginFormValid) {
      showAuthError(context, 'Veuillez remplir tous les champs');
      return;
    }

    setState(() => _isLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      _navigateToNextScreen();
    } else {
      showAuthError(context, 'Email ou mot de passe incorrect');
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.loginWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    if (success) {
      _navigateToNextScreen();
    } else {
      showAuthError(
        context,
        provider.lastAuthErrorMessage ?? 'Connexion Google echouee',
      );
    }
  }

  Future<void> _handleAppleLogin() async {
    setState(() => _isAppleLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.loginWithApple();

    if (!mounted) return;
    setState(() => _isAppleLoading = false);
    if (success) {
      _navigateToNextScreen();
    } else {
      showAuthError(
        context,
        provider.lastAuthErrorMessage ?? 'Connexion Apple echouee',
      );
    }
  }

  Future<void> _handleRegister() async {
    if (_usernameCtrl.text.trim().isEmpty) {
      showAuthError(context, "Le nom d'utilisateur est requis");
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      showAuthError(context, 'Le numero de telephone est requis');
      return;
    }
    if (!_isValidEmail(_emailCtrl.text.trim())) {
      showAuthError(context, 'Adresse email invalide');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      showAuthError(context, 'Le mot de passe est requis');
      return;
    }
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      showAuthError(context, 'Les mots de passe ne correspondent pas');
      return;
    }

    setState(() => _isLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.registerDirector(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      fullName: _usernameCtrl.text.trim(),
      phone: _fullPhoneNumber,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TermsScreen()),
        (route) => false,
      );
    } else {
      showAuthError(context, "Erreur lors de l'inscription");
    }
  }

  Future<void> _handleGoogleRegister() async {
    setState(() => _isGoogleLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.loginWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    if (success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TermsScreen()),
        (route) => false,
      );
    } else {
      showAuthError(
        context,
        provider.lastAuthErrorMessage ?? 'Inscription Google echouee',
      );
    }
  }

  Future<void> _handleAppleRegister() async {
    setState(() => _isAppleLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final bool success = await provider.loginWithApple();

    if (!mounted) return;
    setState(() => _isAppleLoading = false);
    if (success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TermsScreen()),
        (route) => false,
      );
    } else {
      showAuthError(
        context,
        provider.lastAuthErrorMessage ?? 'Inscription Apple echouee',
      );
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(mode: AuthMode.register),
      ),
    );
  }

  void _navigateToLogin() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  void _navigateToNextScreen() {
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final user = provider.currentUser;
    if (user != null && user.role == UserRoles.director) {
      resolveManagerDestination().then((nextScreen) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => nextScreen),
        );
      });
    } else if (AppSessionService.hasCondoAccess &&
        AppSessionService.currentUserId.isNotEmpty) {
      resolveSessionDestination(AppSessionService.currentUserId).then((
        nextScreen,
      ) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => nextScreen),
        );
      });
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  String get _fullPhoneNumber =>
      '+${_selectedCountry.phoneCode}${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  void _showCountryPickerSheet() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country country) {
        setState(() => _selectedCountry = country);
      },
      countryListTheme: CountryListThemeData(
        backgroundColor: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        inputDecoration: InputDecoration(
          hintText: 'Rechercher un pays ou un indicatif',
          prefixIcon: const Icon(LucideIcons.search, color: kAuthGoldDark),
          hintStyle: GoogleFonts.manrope(
            color: const Color(0xFF8A8A8A),
            fontSize: 14,
          ),
          filled: true,
          fillColor: const Color(0xFFFFFDF8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kAuthBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kAuthBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kAuthGoldDark),
          ),
        ),
        searchTextStyle: GoogleFonts.manrope(
          color: kAuthText,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        textStyle: GoogleFonts.manrope(
          color: kAuthText,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.75,
      ),
    );
  }

  String _flagEmoji(String countryCode) {
    return countryCode
        .toUpperCase()
        .codeUnits
        .map((codeUnit) => String.fromCharCode(codeUnit + 127397))
        .join();
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailCtrl.text.trim());
    bool isSending = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitReset() async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                setDialogState(() {
                  errorText = 'Veuillez saisir votre adresse email.';
                });
                return;
              }

              if (!_isValidEmail(email)) {
                setDialogState(() {
                  errorText = 'Adresse email invalide.';
                });
                return;
              }

              setDialogState(() {
                isSending = true;
                errorText = null;
              });

              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);
                if (!mounted || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                showAuthError(
                  this.context,
                  'Un email de reinitialisation a ete envoye.',
                );
              } on FirebaseAuthException catch (e) {
                String message =
                    "Impossible d'envoyer l'email de reinitialisation.";
                if (e.code == 'user-not-found') {
                  message = 'Aucun compte trouve avec cette adresse email.';
                } else if (e.code == 'invalid-email') {
                  message = 'Adresse email invalide.';
                }

                setDialogState(() {
                  isSending = false;
                  errorText = message;
                });
              } catch (_) {
                setDialogState(() {
                  isSending = false;
                  errorText =
                      "Impossible d'envoyer l'email de reinitialisation.";
                });
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  color: kAuthPanel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: kAuthGold.withValues(alpha: 0.32),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 28,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mot de passe oublie ?',
                      style: GoogleFonts.cormorantGaramond(
                        color: kAuthText,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Entrez votre adresse email pour recevoir un lien de reinitialisation.',
                      style: GoogleFonts.manrope(
                        color: kAuthMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LuxuryInput(
                      controller: emailController,
                      hint: 'Adresse E-mail',
                      keyboardType: TextInputType.emailAddress,
                      prefix: const Icon(
                        LucideIcons.mail,
                        color: kAuthGoldDark,
                        size: 21,
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: GoogleFonts.manrope(
                          color: const Color(0xFFB3261E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _BlackGoldButton(
                      label: 'Envoyer',
                      isLoading: isSending,
                      onPressed: isSending ? null : submitReset,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: isSending
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: kAuthText,
                        ),
                        child: Text(
                          'Annuler',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: kAuthPanel,
      resizeToAvoidBottomInset: false,
      body: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactHeight = constraints.maxHeight < 760;
            final heroHeight =
                (constraints.maxHeight * (_isLogin ? 0.52 : 0.40)).clamp(
              _isLogin
                  ? (isCompactHeight ? 300.0 : 340.0)
                  : (isCompactHeight ? 240.0 : 270.0),
              _isLogin
                  ? (isCompactHeight ? 420.0 : 460.0)
                  : (isCompactHeight ? 340.0 : 380.0),
            );

            return SizedBox(
              height: constraints.maxHeight,
              child: Stack(
                children: [
                  _AuthHero(
                    height: heroHeight,
                    showBack: false,
                  ),
                  Positioned(
                    top: heroHeight - 26,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _AuthPanel(
                      bottomInset: mediaQuery.padding.bottom,
                      child: _isLogin
                          ? _buildLoginContent(isCompactHeight)
                          : _buildRegisterContent(isCompactHeight),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginContent(bool isCompactHeight) {
    final titleSize = isCompactHeight ? 28.0 : 32.0;
    final bodySize = isCompactHeight ? 13.0 : 14.0;
    final gap = isCompactHeight ? 8.0 : 10.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenue',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: kAuthGoldDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Connexion',
          style: GoogleFonts.cormorantGaramond(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: kAuthText,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Accedez a votre espace de gestion',
          style: GoogleFonts.manrope(
            fontSize: bodySize,
            fontWeight: FontWeight.w500,
            color: kAuthMuted,
          ),
        ),
        SizedBox(height: isCompactHeight ? 10 : 12),
        _LuxuryInput(
          controller: _emailCtrl,
          hint: 'Adresse E-mail',
          keyboardType: TextInputType.emailAddress,
          prefix: const Icon(LucideIcons.mail, color: kAuthGoldDark, size: 21),
          onChanged: (_) => setState(() {}),
          dense: isCompactHeight,
        ),
        SizedBox(height: gap),
        _LuxuryInput(
          controller: _passwordCtrl,
          hint: 'Mot de passe',
          obscureText: _obscurePassword,
          prefix: const Icon(LucideIcons.lock, color: kAuthText, size: 21),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
              color: kAuthText,
              size: 21,
            ),
          ),
          onChanged: (_) => setState(() {}),
          dense: isCompactHeight,
        ),
        SizedBox(height: gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(999),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _rememberMe ? kAuthText : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _rememberMe ? kAuthText : kAuthBorder,
                        ),
                      ),
                      child: _rememberMe
                          ? const Icon(
                              LucideIcons.check,
                              color: Colors.white,
                              size: 14,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Se souvenir de moi',
                      style: GoogleFonts.manrope(
                        color: kAuthText,
                        fontSize: isCompactHeight ? 12.8 : 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _showForgotPasswordDialog,
              child: Text(
                'Mot de passe oublie ?',
                style: GoogleFonts.manrope(
                  color: kAuthGoldDark,
                  fontSize: isCompactHeight ? 12.8 : 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isCompactHeight ? 10 : 12),
        _BlackGoldButton(
          label: 'Se connecter',
          isLoading: _isLoading && !_hasSavedUser,
          onPressed: _isLoading ? null : _handleLogin,
          compact: isCompactHeight,
        ),
        SizedBox(height: isCompactHeight ? 8 : 10),
        const _SectionDivider(),
        SizedBox(height: isCompactHeight ? 8 : 10),
        _GoogleButton(
          isLoading: _isGoogleLoading,
          onPressed: _isGoogleLoading ? null : _handleGoogleLogin,
          compact: isCompactHeight,
        ),
        if (_supportsAppleSignIn) ...[
          SizedBox(height: isCompactHeight ? 6 : 8),
          _AppleButton(
            isLoading: _isAppleLoading,
            onPressed: _isAppleLoading ? null : _handleAppleLogin,
            compact: isCompactHeight,
          ),
        ],
        SizedBox(height: isCompactHeight ? 6 : 8),
        Center(
          child: InkWell(
            onTap: _navigateToRegister,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.only(top: isCompactHeight ? 4 : 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.user,
                    color: kAuthGoldDark,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.manrope(
                        color: kAuthText,
                        fontSize: isCompactHeight ? 13 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: 'Pas de compte ? '),
                        TextSpan(
                          text: 'Inscrivez-vous',
                          style: GoogleFonts.manrope(
                            color: kAuthGoldDark,
                            fontSize: isCompactHeight ? 13 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterContent(bool isCompactHeight) {
    final titleSize = isCompactHeight ? 27.0 : 30.0;
    final bodySize = isCompactHeight ? 12.5 : 13.0;
    final fieldGap = isCompactHeight ? 6.0 : 8.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenue',
          style: GoogleFonts.cormorantGaramond(
            fontSize: isCompactHeight ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: kAuthGoldDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Creer un compte',
          style: GoogleFonts.cormorantGaramond(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: kAuthText,
            height: 0.98,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Creez votre espace de gestion',
          style: GoogleFonts.manrope(
            fontSize: bodySize,
            fontWeight: FontWeight.w500,
            color: kAuthMuted,
          ),
        ),
        SizedBox(height: isCompactHeight ? 8 : 10),
        _LuxuryInput(
          controller: _usernameCtrl,
          hint: "Nom d'utilisateur",
          keyboardType: TextInputType.name,
          prefix: const Icon(LucideIcons.user, color: kAuthText, size: 21),
          onChanged: (_) => setState(() {}),
          dense: true,
        ),
        SizedBox(height: fieldGap),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: _CountryPickerField(
                flag: _flagEmoji(_selectedCountry.countryCode),
                dialCode: '+${_selectedCountry.phoneCode}',
                onTap: _showCountryPickerSheet,
                dense: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 9,
              child: _LuxuryInput(
                controller: _phoneCtrl,
                hint: 'Numero de telephone',
                keyboardType: TextInputType.phone,
                prefix:
                    const Icon(LucideIcons.phone, color: kAuthText, size: 21),
                onChanged: (_) => setState(() {}),
                dense: true,
              ),
            ),
          ],
        ),
        SizedBox(height: fieldGap),
        _LuxuryInput(
          controller: _emailCtrl,
          hint: 'Adresse E-mail',
          keyboardType: TextInputType.emailAddress,
          prefix: const Icon(LucideIcons.mail, color: kAuthText, size: 21),
          onChanged: (_) => setState(() {}),
          dense: true,
        ),
        SizedBox(height: fieldGap),
        _LuxuryInput(
          controller: _passwordCtrl,
          hint: 'Mot de passe',
          obscureText: _obscurePassword,
          prefix: const Icon(LucideIcons.lock, color: kAuthText, size: 21),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
              color: kAuthText,
              size: 21,
            ),
          ),
          onChanged: (_) => setState(() {}),
          dense: true,
        ),
        SizedBox(height: fieldGap),
        _LuxuryInput(
          controller: _confirmPasswordCtrl,
          hint: 'Confirmer le mot de passe',
          obscureText: _obscureConfirmPassword,
          prefix: const Icon(LucideIcons.lock, color: kAuthText, size: 21),
          suffix: IconButton(
            onPressed: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword,
            ),
            icon: Icon(
              _obscureConfirmPassword ? LucideIcons.eye : LucideIcons.eyeOff,
              color: kAuthText,
              size: 21,
            ),
          ),
          onChanged: (_) => setState(() {}),
          dense: true,
        ),
        SizedBox(height: isCompactHeight ? 8 : 10),
        _BlackGoldButton(
          label: 'Creer un compte',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _handleRegister,
          compact: true,
        ),
        SizedBox(height: isCompactHeight ? 6 : 8),
        const _SectionDivider(),
        SizedBox(height: isCompactHeight ? 6 : 8),
        _GoogleButton(
          isLoading: _isGoogleLoading,
          onPressed: _isGoogleLoading ? null : _handleGoogleRegister,
          compact: true,
        ),
        if (_supportsAppleSignIn) ...[
          SizedBox(height: isCompactHeight ? 6 : 8),
          _AppleButton(
            isLoading: _isAppleLoading,
            onPressed: _isAppleLoading ? null : _handleAppleRegister,
            compact: true,
          ),
        ],
        SizedBox(height: isCompactHeight ? 6 : 8),
        Center(
          child: InkWell(
            onTap: _navigateToLogin,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.only(top: isCompactHeight ? 2 : 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.user,
                    color: kAuthGoldDark,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.manrope(
                        color: kAuthText,
                        fontSize: isCompactHeight ? 13 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: 'Deja un compte ? '),
                        TextSpan(
                          text: 'Connectez-vous',
                          style: GoogleFonts.manrope(
                            color: kAuthGoldDark,
                            fontSize: isCompactHeight ? 13 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.height,
    required this.showBack,
  });

  final double height;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/authheroimg.webp',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(color: kAuthBg),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.62, 1.0],
                  colors: [
                    Color(0x14000000),
                    Color(0x12000000),
                    Color(0xA0050505),
                  ],
                ),
              ),
            ),
            if (showBack)
              Positioned(
                top: topPadding + 12,
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
                            color: kAuthText,
                            size: 20,
                          ),
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

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.child,
    required this.bottomInset,
  });

  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Transform.translate(
        offset: const Offset(0, -26),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: kAuthPanel,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(40),
              topRight: Radius.circular(40),
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
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding =
                    EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 2);
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: padding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - padding.vertical,
                    ),
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryPickerField extends StatelessWidget {
  const _CountryPickerField({
    required this.flag,
    required this.dialCode,
    required this.onTap,
    this.dense = false,
  });

  final String flag;
  final String dialCode;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: dense ? 48 : 52,
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kAuthBorder),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dialCode,
                style: GoogleFonts.manrope(
                  color: kAuthText,
                  fontSize: dense ? 14 : 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              LucideIcons.chevronDown,
              color: kAuthText,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _LuxuryInput extends StatefulWidget {
  const _LuxuryInput({
    required this.controller,
    required this.hint,
    required this.prefix,
    this.suffix,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.dense = false,
  });

  final TextEditingController controller;
  final String hint;
  final Widget prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final bool dense;

  @override
  State<_LuxuryInput> createState() => _LuxuryInputState();
}

class _LuxuryInputState extends State<_LuxuryInput> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: widget.dense ? 48 : 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused ? kAuthGoldDark : kAuthBorder,
          width: _isFocused ? 1.25 : 1.0,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        onChanged: widget.onChanged,
        style: GoogleFonts.manrope(
          color: kAuthText,
          fontSize: widget.dense ? 15 : 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: GoogleFonts.manrope(
            color: const Color(0xFF8A8A8A),
            fontSize: widget.dense ? 15 : 16,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: widget.prefix,
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: 48,
            minHeight: widget.dense ? 48 : 52,
          ),
          suffixIcon: widget.suffix,
          contentPadding: EdgeInsets.symmetric(
            vertical: widget.dense ? 12 : 14,
          ),
        ),
      ),
    );
  }
}

class _BlackGoldButton extends StatelessWidget {
  const _BlackGoldButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 54.0 : 58.0;
    final arrowSize = compact ? 38.0 : 42.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: const Color(0xFF0B0B0B),
            border: Border.all(color: kAuthGold, width: 1.1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: arrowSize,
                  height: arrowSize,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF0CB87),
                        Color(0xFFD6A85A),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    LucideIcons.arrowRight,
                    color: Colors.black,
                    size: compact ? 19 : 21,
                  ),
                ),
              ),
              isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 32 : 36,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: compact ? 15.5 : 16.5,
                          fontWeight: FontWeight.w600,
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

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: kAuthDivider, thickness: 1, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OU',
            style: GoogleFonts.manrope(
              color: kAuthMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: kAuthDivider, thickness: 1, height: 1),
        ),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.isLoading,
    required this.onPressed,
    this.compact = false,
  });

  final bool isLoading;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        height: compact ? 52 : 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kAuthBorder),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: kAuthText,
                  strokeWidth: 2.2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleGlyph(size: compact ? 20 : 22),
                  SizedBox(width: compact ? 12 : 14),
                  Text(
                    'Continuer avec Google',
                    style: GoogleFonts.cormorantGaramond(
                      color: kAuthText,
                      fontSize: compact ? 17 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/google-icon-logo-svgrepo-com.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({
    required this.isLoading,
    required this.onPressed,
    this.compact = false,
  });

  final bool isLoading;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        height: compact ? 52 : 56,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF222222)),
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.apple, color: Colors.white, size: 22),
                  SizedBox(width: compact ? 12 : 14),
                  Text(
                    'Continuer avec Apple',
                    style: GoogleFonts.cormorantGaramond(
                      color: Colors.white,
                      fontSize: compact ? 17 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

void showAuthError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF111111),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: kAuthGold.withValues(alpha: 0.45),
          width: 0.9,
        ),
      ),
      content: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: kAuthGold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
