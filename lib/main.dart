import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hotel_lux_os/core/manager_session_guard.dart';
import 'package:hotel_lux_os/core/firebase_options.dart';
import 'package:hotel_lux_os/core/theme.dart';
import 'package:hotel_lux_os/providers/hotel_provider.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/screens/dashboard_screen.dart';
import 'package:hotel_lux_os/screens/manager_device_lock_screen.dart';
import 'package:hotel_lux_os/screens/manager_navigation.dart';
import 'package:lottie/lottie.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    runApp(ErrorApp(error: e.toString()));
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HotelProvider()),
      ],
      child: const HotelApp(),
    ),
  );
}

class HotelApp extends StatelessWidget {
  const HotelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "STAYFIX MANAGER",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashPage(),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red[900],
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: SingleChildScrollView(
              child: Text(
                "Firebase initialization error:\n\n$error",
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final nextScreenFuture = _resolveNextScreen();
    final lottieLoadFuture = AssetLottie('assets/lottie/loading.json').load();

    final results = await Future.wait<Object?>([
      nextScreenFuture,
      lottieLoadFuture,
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);

    if (!mounted) return;
    final Widget nextScreen = results[0]! as Widget;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  Future<Widget> _resolveNextScreen() async {
    final provider = Provider.of<HotelProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final String? savedUserId = prefs.getString('userId');

    if (savedUserId == null || savedUserId.isEmpty) {
      return const AuthScreen();
    }

    await provider.tryAutoLogin();

    if (provider.currentUser == null) {
      return const AuthScreen();
    }

    if (provider.isDirector) {
      if (FirebaseAuth.instance.currentUser == null) {
        await provider.logout();
        return const AuthScreen();
      }

      if (!ManagerSessionGuard.isUnlockedThisRuntime) {
        return const ManagerDeviceLockScreen(
          destinationBuilder: resolveManagerDestination,
        );
      }

      return resolveManagerDestination();
    }

    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: "Veuillez vous authentifier pour acceder a Stayfix",
        );

        if (!didAuthenticate) {
          return const AuthScreen();
        }
      }
    } catch (e) {
      debugPrint("Biometric error: $e");
    }

    if (provider.isDirector) {
      return resolveManagerDestination();
    }
    return const DashboardScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0B0B0B),
                  Color(0xFF15120E),
                  Color(0xFF050505),
                ],
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD6A85A).withValues(alpha: 0.14),
                ),
              ),
            ),
          ),
          Positioned(
            top: 250,
            left: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB8863B).withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/icons/stayfix.webp',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Times New Roman',
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Stay',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'Fix',
                                    style: TextStyle(
                                      color: Color(0xFFD6A85A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Excellence en gestion, hospitalite maitrisee.",
                              style: TextStyle(
                                color: Color(0xC7FFFFFF),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            width: double.infinity,
                            height: 280,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.04),
                                  const Color(
                                    0xFFD6A85A,
                                  ).withValues(alpha: 0.08),
                                  Colors.black.withValues(alpha: 0.10),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  blurRadius: 26,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: SizedBox(
                              height: 280,
                              child: Lottie.asset(
                                'assets/lottie/loading.json',
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => const Icon(
                                  Icons.domain,
                                  size: 110,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(30, 26, 30, 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFDF8),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(36),
                        topRight: Radius.circular(36),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 30,
                          offset: Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Bienvenue",
                          style: TextStyle(
                            color: Color(0xFFB8863B),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ).animate().fadeIn(duration: 300.ms),
                        const SizedBox(height: 8),
                        const Text(
                          "StayFix",
                          style: TextStyle(
                            fontSize: 34,
                            fontFamily: 'Times New Roman',
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111111),
                          ),
                        ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.1),
                        const SizedBox(height: 8),
                        const Text(
                          "Accedez a votre espace de gestion",
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ).animate().fadeIn(delay: 220.ms),
                        const SizedBox(height: 18),
                        Container(
                          width: 78,
                          height: 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFD6A85A),
                                Color(0xFFB8863B),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFE7E0D6),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x10000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFF0CB87),
                                      Color(0xFFD6A85A),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  color: Color(0xFF111111),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "Preparation de votre espace",
                                      style: TextStyle(
                                        color: Color(0xFF111111),
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.all(
                                          Radius.circular(999)),
                                      child: LinearProgressIndicator(
                                        minHeight: 6,
                                        value: 0.72,
                                        backgroundColor: Color(0xFFF1ECE3),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Color(0xFFD6A85A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.12),
                      ],
                    ),
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
