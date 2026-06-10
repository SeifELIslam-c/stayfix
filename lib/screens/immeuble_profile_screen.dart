import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'auth_screen.dart';
import 'building_management_screen.dart';
import 'intervenants_screen.dart';
import 'manager_messages_screen.dart';
import 'manager_offers_screen.dart';
import 'privacy_account_center_screen.dart';
import 'manager_property_route_helper.dart';
import '../services/app_session_service.dart';
import '../services/vps_media_service.dart';
import '../widgets/unread_messages_nav_item.dart';
import '../widgets/google_address_picker_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/hotel_provider.dart';

const _kBg = Color(0xFF070707);
const _kCard = Color(0xFF111111);
const _kMutedCard = Color(0xFF171717);
const _kBorder = Color(0x33D6A85A);
const _kFallbackMapsKey = '';

class _ProfilePageData {
  const _ProfilePageData({
    required this.userData,
    required this.condoId,
    required this.condoName,
    required this.condoLocation,
    required this.availableWorkers,
    required this.apartmentCount,
  });

  final Map<String, dynamic> userData;
  final String? condoId;
  final String? condoName;
  final String? condoLocation;
  final int availableWorkers;
  final int apartmentCount;
}

class _PreferenceToggleItem {
  const _PreferenceToggleItem({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
}

class ImmeubleProfileScreen extends StatefulWidget {
  const ImmeubleProfileScreen({
    super.key,
    required this.propertyType,
  });

  final String propertyType;

  @override
  State<ImmeubleProfileScreen> createState() => _ImmeubleProfileScreenState();
}

class _ImmeubleProfileScreenState extends State<ImmeubleProfileScreen> {
  late Future<_ProfilePageData> _dataFuture;
  int _refreshSeed = 0;
  bool _isSaving = false;

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  @override
  void initState() {
    super.initState();
    _reloadData();
  }

  void _reloadData() {
    final uid = _uid;
    _dataFuture = _loadData(uid);
  }

  Future<_ProfilePageData> _loadData(String uid) async {
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(uid).get(),
      FirebaseFirestore.instance
          .collection('profiles')
          .where('isAvailable', isEqualTo: true)
          .get(),
    ]);

    final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final workersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

    final userData = userDoc.data() ?? <String, dynamic>{};
    final accountType =
        (userData['accountType'] as String?)?.trim().toLowerCase();
    final propertyIds = ((userData['propertyIds'] as List?) ?? const [])
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .toList();
    String? condoId;
    String? condoName;
    String? condoLocation;
    var apartmentCount = 0;

    DocumentSnapshot<Map<String, dynamic>>? propertyDoc;
    if (accountType == 'manager' || accountType == 'concierge') {
      for (final propertyId in propertyIds) {
        final doc = await FirebaseFirestore.instance
            .collection('hotels')
            .doc(propertyId)
            .get();
        if (doc.exists) {
          propertyDoc = doc;
          break;
        }
      }
    } else {
      final propertySnap = await FirebaseFirestore.instance
          .collection('hotels')
          .where('ownerId', isEqualTo: uid)
          .get();
      apartmentCount = propertySnap.docs
          .where((doc) =>
              ((doc.data()['status'] as String?)?.trim().toLowerCase() ??
                  'active') !=
              'deleted')
          .length;
      if (propertySnap.docs.isNotEmpty) {
        propertyDoc = propertySnap.docs.first;
      }
    }

    if (propertyDoc != null && propertyDoc.exists) {
      final condoDoc = propertyDoc;
      condoId = condoDoc.id;
      final condoData = condoDoc.data() ?? const <String, dynamic>{};
      condoName = (condoData['name'] as String?)?.trim();
      condoLocation = (condoData['location'] as String?)?.trim();
    }

    final availableWorkers = workersSnap.docs.where((doc) {
      final data = doc.data();
      final department = (data['department'] as String?)?.trim() ?? '';
      final acceptedTerms = data['termsAccepted'] == true;
      return department.isNotEmpty && acceptedTerms;
    }).length;

    return _ProfilePageData(
      userData: userData,
      condoId: condoId,
      condoName: condoName,
      condoLocation: condoLocation,
      availableWorkers: availableWorkers,
      apartmentCount: apartmentCount,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _refreshSeed++;
      _reloadData();
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kCard,
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

  Future<void> _withSaving(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await action();
      await _refresh();
      _showSnack(successMessage);
    } catch (error) {
      _showSnack('Impossible d enregistrer pour le moment.');
      debugPrint('Immeuble profile save error: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _updateManagerName(String fullName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return;
    final parts =
        trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final firstName = parts.isNotEmpty ? parts.first : trimmed;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    await _withSaving(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'username': trimmed,
      }, SetOptions(merge: true));
      await user.updateDisplayName(trimmed);
    }, successMessage: 'Nom mis a jour.');
  }

  Future<void> _updateManagerAddress(String address) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    await _withSaving(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'address': trimmed,
      }, SetOptions(merge: true));
    }, successMessage: 'Adresse mise a jour.');
  }

  Future<void> _updatePhone({
    required String dialCode,
    required String nationalNumber,
    required String countryIso,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final cleanedNational = nationalNumber.replaceAll(RegExp(r'\D'), '');
    final cleanedDial = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedNational.isEmpty || cleanedDial.isEmpty) return;
    final fullPhone = '+$cleanedDial$cleanedNational';

    await _withSaving(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'phone': fullPhone,
        'phoneDialCode': '+$cleanedDial',
        'phoneNational': cleanedNational,
        'phoneCountryIso': countryIso.toUpperCase(),
      }, SetOptions(merge: true));
    }, successMessage: 'Telephone mis a jour.');
  }

  Future<void> _savePreferenceGroup(
    String group,
    Map<String, dynamic> values,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _withSaving(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'managerPreferences': {
          group: values,
        },
      }, SetOptions(merge: true));
    }, successMessage: 'Preferences enregistrees.');
  }

  Future<void> _openPhotoPicker() async {
    if (_isSaving) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                _MediaOptionTile(
                  icon: LucideIcons.image,
                  title: 'Galerie',
                  subtitle: 'Choisir une photo de profil depuis la galerie',
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
                ),
                const SizedBox(height: 10),
                _MediaOptionTile(
                  icon: LucideIcons.camera,
                  title: 'Camera',
                  subtitle: 'Prendre une nouvelle photo de profil',
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (picked == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _withSaving(() async {
      final uploaded = await VpsMediaService.uploadFile(
        file: File(picked.path),
        category: 'profile-photo',
      );
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': uploaded.url,
        'photoBase64': FieldValue.delete(),
        'profilePhotoBase64': FieldValue.delete(),
        'imageBase64': FieldValue.delete(),
      }, SetOptions(merge: true));
      await user.updatePhotoURL(uploaded.url);
    }, successMessage: 'Photo de profil mise a jour.');
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Se deconnecter ?',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Vous serez redirige vers la page de connexion.',
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Annuler',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
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
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Confirmer',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await Provider.of<HotelProvider>(context, listen: false).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _openNameEditor(String initialValue) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TextEditSheet(
        title: 'Modifier votre nom',
        hint: 'Nom complet',
        icon: LucideIcons.user,
        initialValue: initialValue,
        actionLabel: 'Enregistrer',
      ),
    );
    if (result == null) return;
    await _updateManagerName(result);
  }

  Future<void> _openAddressEditor(String initialValue) async {
    final mapsKey = await _readMapsKey();
    if (!mounted) return;
    final pickedAddress = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoogleAddressPickerSheet(
        title: 'Choisir votre adresse',
        apiKey: mapsKey,
        initialValue: initialValue,
      ),
    );
    if (pickedAddress == null) return;
    await _updateManagerAddress(pickedAddress);
  }

  Future<void> _openPhoneEditor(Map<String, dynamic> userData) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhoneEditSheet(
        initialDialCode:
            _nonEmpty((userData['phoneDialCode'] as String?)?.trim()) ?? '+1',
        initialCountryIso:
            _nonEmpty((userData['phoneCountryIso'] as String?)?.trim())
                    ?.toUpperCase() ??
                'CA',
        initialNationalNumber:
            _nonEmpty((userData['phoneNational'] as String?)?.trim()) ??
                ((userData['phone'] as String?)?.trim() ?? '')
                    .replaceAll(RegExp(r'^\+\d{1,4}'), ''),
      ),
    );

    if (result == null) return;
    await _updatePhone(
      dialCode: result['dialCode'] ?? '+1',
      nationalNumber: result['nationalNumber'] ?? '',
      countryIso: result['countryIso'] ?? 'CA',
    );
  }

  Future<void> _openCondoEditor(_ProfilePageData data) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BuildingManagementScreen(),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openNotificationPreferences(
      Map<String, dynamic> userData) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TogglePreferencesScreen(
          title: 'Notifications',
          subtitle: 'Gardez le controle sur les alertes importantes.',
          heroIcon: LucideIcons.bell,
          initialValues: _notificationPrefs(userData),
          items: const [
            _PreferenceToggleItem(
              keyName: 'messages',
              title: 'Messages',
              subtitle: 'Alerte quand un agent ou un contact vous ecrit.',
              icon: LucideIcons.messageCircle,
            ),
            _PreferenceToggleItem(
              keyName: 'agentAvailability',
              title: 'Agents disponibles',
              subtitle:
                  'Recevoir une alerte quand un agent proche devient libre.',
              icon: LucideIcons.users,
            ),
            _PreferenceToggleItem(
              keyName: 'offerUpdates',
              title: 'Offres et demandes',
              subtitle:
                  'Suivi des nouvelles demandes et de leurs mises a jour.',
              icon: LucideIcons.clipboardList,
            ),
            _PreferenceToggleItem(
              keyName: 'dailySummary',
              title: 'Resume quotidien',
              subtitle:
                  'Un recap rapide de votre activite manager chaque jour.',
              icon: LucideIcons.calendarDays,
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await _savePreferenceGroup('notifications', result);
  }

  Future<void> _openPrivacyPreferences(Map<String, dynamic> userData) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TogglePreferencesScreen(
          title: 'Confidentialite',
          subtitle:
              'Parametres manager inspires du niveau de detail attendu dans StayFix.',
          heroIcon: LucideIcons.shieldCheck,
          initialValues: _privacyPrefs(userData),
          items: const [
            _PreferenceToggleItem(
              keyName: 'shareManagerName',
              title: 'Partager mon nom',
              subtitle:
                  'Afficher votre nom au moment des prises de contact avec les agents.',
              icon: LucideIcons.user,
            ),
            _PreferenceToggleItem(
              keyName: 'shareExactCondoAddress',
              title: 'Partager l adresse exacte',
              subtitle:
                  'Montrer l adresse complete de l immeuble uniquement si necessaire.',
              icon: LucideIcons.mapPin,
            ),
            _PreferenceToggleItem(
              keyName: 'sharePhoneWithSelectedAgents',
              title: 'Partager mon telephone',
              subtitle:
                  'Autoriser les agents selectionnes a voir votre numero direct.',
              icon: LucideIcons.phone,
            ),
            _PreferenceToggleItem(
              keyName: 'showOnlyTermsAcceptedWorkers',
              title: 'Montrer seulement les agents conformes',
              subtitle:
                  'Garder la priorite sur les agents qui ont accepte leurs termes et complete leur profil.',
              icon: LucideIcons.badgeCheck,
            ),
            _PreferenceToggleItem(
              keyName: 'requireCvBeforeSelection',
              title: 'Exiger un CV avant selection',
              subtitle:
                  'Filtrer votre gestion vers les profils prets a etre revus.',
              icon: LucideIcons.fileCheck,
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await _savePreferenceGroup('privacy', result);
  }

  Future<void> _openSecurityPreferences(Map<String, dynamic> userData) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _TogglePreferencesScreen(
          title: 'Securite',
          subtitle: 'Renforcez la protection de votre espace manager.',
          heroIcon: LucideIcons.lock,
          initialValues: _securityPrefs(userData),
          items: const [
            _PreferenceToggleItem(
              keyName: 'biometricLock',
              title: 'Verrou biometrie',
              subtitle:
                  'Garder une authentification locale active au retour dans l app.',
              icon: LucideIcons.fingerprint,
            ),
            _PreferenceToggleItem(
              keyName: 'loginAlerts',
              title: 'Alertes de connexion',
              subtitle:
                  'Etre informe quand votre session est rouverte sur un appareil.',
              icon: LucideIcons.bellRing,
            ),
            _PreferenceToggleItem(
              keyName: 'sensitiveDataShield',
              title: 'Masquer les donnees sensibles',
              subtitle:
                  'Limiter l exposition des coordonnees completes dans les apercus.',
              icon: LucideIcons.shield,
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await _savePreferenceGroup('security', result);
  }

  Future<void> _openAppPreferences(Map<String, dynamic> userData) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _ApplicationPreferencesScreen(
          initialValues: _applicationPrefs(userData),
        ),
      ),
    );

    if (result == null) return;
    await _savePreferenceGroup('application', result);
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || _uid.isEmpty) return const AuthScreen();

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _buildBottomNav(),
      body: FutureBuilder<_ProfilePageData>(
        key: ValueKey(_refreshSeed),
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                color: kAuthGold,
                strokeWidth: 2,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      color: kAuthGold,
                      size: 28,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Impossible de charger votre profil pour le moment.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _refresh,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: kAuthGold.withValues(alpha: 0.80),
                        ),
                        foregroundColor: kAuthGold,
                      ),
                      child: const Text('Reessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ??
              const _ProfilePageData(
                userData: <String, dynamic>{},
                condoId: null,
                condoName: null,
                condoLocation: null,
                availableWorkers: 0,
                apartmentCount: 0,
              );
          return _buildContent(firebaseUser, data);
        },
      ),
    );
  }

  Widget _buildContent(User firebaseUser, _ProfilePageData data) {
    final userData = data.userData;
    final displayName = _resolveDisplayName(firebaseUser, userData);
    final accountType =
        (userData['accountType'] as String?)?.trim().toLowerCase();
    final roleLabel = accountType == 'concierge'
        ? 'Concierge immeuble'
        : accountType == 'manager'
            ? 'Gestionnaire immeuble'
            : widget.propertyType == 'rental_building'
                ? 'Immeuble locatif'
                : 'Immeuble copropriete';
    final email =
        _nonEmpty((userData['email'] as String?)?.trim()) ?? firebaseUser.email;
    final phone = _nonEmpty((userData['phone'] as String?)?.trim());
    final address = _nonEmpty((userData['address'] as String?)?.trim());
    final createdAt = userData['createdAt'];
    final memberSince = _formatMemberSince(createdAt, firebaseUser);
    final photoBase64 = (userData['photoBase64'] as String?)?.trim();
    final photoUrl = _nonEmpty((userData['photoUrl'] as String?)?.trim()) ??
        _nonEmpty((userData['photoURL'] as String?)?.trim()) ??
        firebaseUser.photoURL;
    final photoBytes = _decodeBase64Photo(photoBase64);
    final initials = _initials(displayName);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ProfileHero(
            name: displayName,
            role: roleLabel,
            photoBytes: photoBytes,
            photoUrl: photoUrl,
            initials: initials,
            onBack: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => buildManagerHomeScreen(
                  propertyType: widget.propertyType,
                ),
              ),
            ),
            onCameraTap: _openPhotoPicker,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: _CondoCard(
            name: data.condoName,
            location: data.condoLocation,
            onTap: _isSaving ? null : () => _openCondoEditor(data),
            titleOverride: data.apartmentCount > 0
                ? 'Ajouter un autre appartement'
                : 'Ajouter un appartement',
            subtitleOverride: data.apartmentCount > 0
                ? '${data.apartmentCount} appartement(s) deja cree(s). Ouvrir la gestion immeuble.'
                : 'Ouvrir la gestion immeuble pour creer votre premier appartement.',
            actionLabel: 'Gerer',
            icon: LucideIcons.building2,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Apercu manager'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: _QuickStatsGrid(
            availableWorkers: data.availableWorkers,
            onIntervenants: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
            ),
            onMessages: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ManagerMessagesScreen()),
            ),
            onOffres: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ManagerOffersScreen()),
            ),
            onNotifications: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BuildingManagementScreen(),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Profil manager'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: _InfoCard(
            rows: [
              _InfoRowData(
                icon: LucideIcons.user,
                label: 'Nom complet',
                value: displayName,
                onTap: _isSaving ? null : () => _openNameEditor(displayName),
              ),
              _InfoRowData(
                icon: LucideIcons.mail,
                label: 'Email',
                value: email,
                isEditable: false,
              ),
              _InfoRowData(
                icon: LucideIcons.phone,
                label: 'Telephone',
                value: phone,
                onTap: _isSaving ? null : () => _openPhoneEditor(userData),
              ),
              _InfoRowData(
                icon: LucideIcons.mapPin,
                label: 'Adresse',
                value: address,
                onTap:
                    _isSaving ? null : () => _openAddressEditor(address ?? ''),
              ),
              _InfoRowData(
                icon: LucideIcons.calendarDays,
                label: 'Membre depuis',
                value: memberSince,
                isEditable: false,
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Preferences'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: _PrefsCard(
            rows: [
              _PrefRowData(
                icon: LucideIcons.bell,
                title: 'Notifications',
                subtitle: 'Messages, agents proches et resumes.',
                onTap: _isSaving
                    ? null
                    : () => _openNotificationPreferences(userData),
              ),
              _PrefRowData(
                icon: LucideIcons.shieldCheck,
                title: 'Confidentialite',
                subtitle:
                    'Nom manager, adresse, telephone et informations immeuble.',
                onTap:
                    _isSaving ? null : () => _openPrivacyPreferences(userData),
              ),
              _PrefRowData(
                icon: LucideIcons.lock,
                title: 'Securite',
                subtitle: 'Biometrie, alertes de connexion et protection.',
                onTap:
                    _isSaving ? null : () => _openSecurityPreferences(userData),
              ),
              _PrefRowData(
                icon: LucideIcons.settings,
                title: 'Application',
                subtitle: 'Langue, rafraichissement et affichage manager.',
                onTap: _isSaving ? null : () => _openAppPreferences(userData),
              ),
              _PrefRowData(
                icon: LucideIcons.shield,
                title: 'Confidentialite et compte',
                subtitle:
                    'Politique de confidentialite, support et suppression du compte.',
                onTap: _isSaving
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PrivacyAccountCenterScreen(),
                          ),
                        ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : () => showDeleteAccountFlow(context),
              icon: const Icon(LucideIcons.trash2),
              label: const Text('Supprimer mon compte'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF7B7B),
                side: const BorderSide(color: Color(0x66FF7B7B)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: _LogoutButton(
            isLoading: _isSaving,
            onTap: _confirmLogout,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildBottomNav() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        height: 64,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.50),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: LucideIcons.home,
              label: 'Accueil',
              isActive: false,
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => buildManagerHomeScreen(
                    propertyType: widget.propertyType,
                  ),
                ),
              ),
            ),
            _NavItem(
              icon: LucideIcons.users,
              label: 'Agents',
              isActive: false,
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
              ),
            ),
            _NavItem(
              icon: LucideIcons.clipboardList,
              label: 'Offres',
              isActive: false,
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ManagerOffersScreen()),
              ),
            ),
            UnreadMessagesNavItem(
              isActive: false,
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManagerMessagesScreen(),
                ),
              ),
              activeColor: kAuthGold,
              inactiveColor: Colors.white.withValues(alpha: 0.40),
              dotColor: const Color(0xFFFF3B30),
              fontSize: 10,
              activeFontWeight: FontWeight.w600,
              inactiveFontWeight: FontWeight.w400,
            ),
            const _NavItem(
              icon: LucideIcons.user,
              label: 'Profil',
              isActive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.role,
    required this.photoBytes,
    required this.photoUrl,
    required this.initials,
    required this.onBack,
    required this.onCameraTap,
  });

  final String name;
  final String role;
  final Uint8List? photoBytes;
  final String? photoUrl;
  final String initials;
  final VoidCallback onBack;
  final VoidCallback onCameraTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
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
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.94),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      _CircleBtn(icon: LucideIcons.arrowLeft, onTap: onBack),
                      const Spacer(),
                      Text(
                        'Mon profil',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(
                        width: 42,
                        height: 42,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _AvatarWithCamera(
                        photoBytes: photoBytes,
                        photoUrl: photoUrl,
                        initials: initials,
                        onCameraTap: onCameraTap,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Bonjour,',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              role,
                              style: GoogleFonts.inter(
                                color: kAuthGold,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
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
          ),
        ],
      ),
    );
  }
}

class _AvatarWithCamera extends StatelessWidget {
  const _AvatarWithCamera({
    required this.photoBytes,
    required this.photoUrl,
    required this.initials,
    required this.onCameraTap,
  });

  final Uint8List? photoBytes;
  final String? photoUrl;
  final String initials;
  final VoidCallback onCameraTap;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      child = Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          if (photoBytes != null) {
            return Image.memory(photoBytes!, fit: BoxFit.cover);
          }
          return _InitialsFallback(initials: initials);
        },
      );
    } else if (photoBytes != null) {
      child = Image.memory(
        photoBytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    } else {
      child = _InitialsFallback(initials: initials);
    }

    return Stack(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: kAuthGold, width: 2),
          ),
          child: ClipOval(child: child),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: onCameraTap,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: kAuthGold.withValues(alpha: 0.50),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                LucideIcons.camera,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({required this.initials});

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
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

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

class _CondoCard extends StatelessWidget {
  const _CondoCard({
    required this.name,
    required this.location,
    required this.onTap,
    this.titleOverride,
    this.subtitleOverride,
    this.actionLabel = 'Modifier',
    this.icon = LucideIcons.building2,
  });

  final String? name;
  final String? location;
  final VoidCallback? onTap;
  final String? titleOverride;
  final String? subtitleOverride;
  final String actionLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
              ),
              child: Icon(icon, color: kAuthGold, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleOverride ??
                        (name?.isNotEmpty == true
                            ? name!
                            : 'Ajouter votre immeuble'),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleOverride ??
                        (location?.isNotEmpty == true
                            ? location!
                            : 'Nom + adresse de l immeuble'),
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              actionLabel,
              style: GoogleFonts.inter(
                color: kAuthGold,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.30),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuickStatsGrid extends StatelessWidget {
  const _QuickStatsGrid({
    required this.availableWorkers,
    required this.onIntervenants,
    required this.onMessages,
    required this.onOffres,
    required this.onNotifications,
  });

  final int availableWorkers;
  final VoidCallback onIntervenants;
  final VoidCallback onMessages;
  final VoidCallback onOffres;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: [
          _StatCard(
            icon: LucideIcons.clipboardList,
            count: 0,
            label: 'Interventions\nen cours',
            onTap: onMessages,
          ),
          _StatCard(
            icon: LucideIcons.users,
            count: availableWorkers,
            label: 'Agents\nprets a aider',
            onTap: onIntervenants,
          ),
          _StatCard(
            icon: LucideIcons.checkSquare,
            count: 0,
            label: 'Taches\nprioritaires',
            onTap: onOffres,
          ),
          _StatCard(
            icon: LucideIcons.bell,
            count: 0,
            label: 'Alertes\nactives',
            onTap: onNotifications,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.count,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: kAuthGold.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: kAuthGold, size: 18),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 11,
                    height: 1.3,
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

class _InfoRowData {
  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
    this.isEditable = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool isEditable;
  final VoidCallback? onTap;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          return _InfoRow(
            data: row,
            isLast: index == rows.length - 1,
          );
        }),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.data,
    required this.isLast,
  });

  final _InfoRowData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final hasValue = data.value != null && data.value!.isNotEmpty;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(color: kAuthGold.withValues(alpha: 0.25)),
            ),
            child: Icon(data.icon, color: kAuthGold, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              data.label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              hasValue ? data.value! : 'Non renseigne',
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: hasValue
                    ? Colors.white.withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.35),
                fontSize: 13,
              ),
            ),
          ),
          if (data.isEditable) ...[
            const SizedBox(width: 6),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.20),
              size: 14,
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        InkWell(
          onTap: data.isEditable ? data.onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: content,
        ),
        if (!isLast)
          Divider(
            color: Colors.white.withValues(alpha: 0.06),
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _PrefRowData {
  const _PrefRowData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

class _PrefsCard extends StatelessWidget {
  const _PrefsCard({required this.rows});

  final List<_PrefRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          return Column(
            children: [
              InkWell(
                onTap: row.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: kAuthGold.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(row.icon, color: kAuthGold, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.title,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              row.subtitle,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.chevronRight,
                        color: Colors.white.withValues(alpha: 0.30),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              if (index != rows.length - 1)
                Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({
    required this.onTap,
    required this.isLoading,
  });

  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kAuthGoldDark, kAuthGold],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(LucideIcons.logOut, color: Colors.black, size: 18),
              const SizedBox(width: 10),
            ],
            Text(
              isLoading ? 'Enregistrement...' : 'Se deconnecter',
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color:
                  isActive ? kAuthGold : Colors.white.withValues(alpha: 0.40),
              size: isActive ? 22 : 20,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color:
                    isActive ? kAuthGold : Colors.white.withValues(alpha: 0.40),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextEditSheet extends StatefulWidget {
  const _TextEditSheet({
    required this.title,
    required this.hint,
    required this.icon,
    required this.initialValue,
    required this.actionLabel,
  });

  final String title;
  final String hint;
  final IconData icon;
  final String initialValue;
  final String actionLabel;

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetHeader(title: widget.title),
          const SizedBox(height: 16),
          _GoldInput(
            controller: _controller,
            label: widget.hint,
            icon: widget.icon,
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(
            label: widget.actionLabel,
            onTap: () => Navigator.pop(context, _controller.text.trim()),
          ),
        ],
      ),
    );
  }
}

class _PhoneEditSheet extends StatefulWidget {
  const _PhoneEditSheet({
    required this.initialDialCode,
    required this.initialCountryIso,
    required this.initialNationalNumber,
  });

  final String initialDialCode;
  final String initialCountryIso;
  final String initialNationalNumber;

  @override
  State<_PhoneEditSheet> createState() => _PhoneEditSheetState();
}

class _PhoneEditSheetState extends State<_PhoneEditSheet> {
  late final TextEditingController _phoneController;
  late String _dialCode;
  late String _countryIso;

  @override
  void initState() {
    super.initState();
    _phoneController =
        TextEditingController(text: widget.initialNationalNumber);
    _dialCode = widget.initialDialCode;
    _countryIso = widget.initialCountryIso;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        backgroundColor: _kCard,
        textStyle: GoogleFonts.inter(color: Colors.white),
        bottomSheetHeight: 560,
        inputDecoration: InputDecoration(
          hintText: 'Rechercher un pays',
          hintStyle: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.45),
          ),
          prefixIcon: const Icon(LucideIcons.search, color: Colors.white70),
          filled: true,
          fillColor: _kMutedCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      onSelect: (country) {
        setState(() {
          _countryIso = country.countryCode;
          _dialCode = '+${country.phoneCode}';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHeader(title: 'Modifier le telephone'),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _kMutedCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Text(
                    _flagEmoji(_countryIso),
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _dialCode,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronDown,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _GoldInput(
            controller: _phoneController,
            label: 'Numero de telephone',
            icon: LucideIcons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(
            label: 'Enregistrer',
            onTap: () {
              Navigator.pop(context, <String, String>{
                'dialCode': _dialCode,
                'countryIso': _countryIso,
                'nationalNumber': _phoneController.text.trim(),
              });
            },
          ),
        ],
      ),
    );
  }
}

class _CondoEditSheet extends StatefulWidget {
  const _CondoEditSheet({
    required this.initialName,
    required this.initialAddress,
    required this.apiKey,
  });

  final String initialName;
  final String initialAddress;
  final String apiKey;

  @override
  State<_CondoEditSheet> createState() => _CondoEditSheetState();
}

class _CondoEditSheetState extends State<_CondoEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _addressController = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GoogleAddressPickerScreen(
          title: 'Choisir l adresse de l immeuble',
          apiKey: widget.apiKey,
          initialAddress: _addressController.text.trim(),
        ),
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    setState(() => _addressController.text = result);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHeader(title: 'Modifier l immeuble'),
          const SizedBox(height: 16),
          _GoldInput(
            controller: _nameController,
            label: 'Nom de l immeuble',
            icon: LucideIcons.building2,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickAddress,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _kMutedCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.mapPin, color: kAuthGold, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _addressController.text.trim().isNotEmpty
                          ? _addressController.text.trim()
                          : 'Choisir une adresse Google Maps',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _addressController.text.trim().isNotEmpty
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.50),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(
            label: 'Enregistrer',
            onTap: () => Navigator.pop(context, <String, String>{
              'name': _nameController.text.trim(),
              'address': _addressController.text.trim(),
            }),
          ),
        ],
      ),
    );
  }
}

class _TogglePreferencesScreen extends StatefulWidget {
  const _TogglePreferencesScreen({
    required this.title,
    required this.subtitle,
    required this.heroIcon,
    required this.initialValues,
    required this.items,
  });

  final String title;
  final String subtitle;
  final IconData heroIcon;
  final Map<String, dynamic> initialValues;
  final List<_PreferenceToggleItem> items;

  @override
  State<_TogglePreferencesScreen> createState() =>
      _TogglePreferencesScreenState();
}

class _TogglePreferencesScreenState extends State<_TogglePreferencesScreen> {
  late final Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      heroIcon: widget.heroIcon,
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        itemCount: widget.items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == widget.items.length) {
            return _PrimaryActionButton(
              label: 'Enregistrer',
              onTap: () => Navigator.pop(context, _values),
            );
          }

          final item = widget.items[index];
          final currentValue = _values[item.keyName] == true;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kAuthGold.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(item.icon, color: kAuthGold, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: currentValue,
                  activeThumbColor: Colors.black,
                  activeTrackColor: const Color(0xFF22C55E),
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white24,
                  onChanged: (value) {
                    setState(() => _values[item.keyName] = value);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationPreferencesScreen extends StatefulWidget {
  const _ApplicationPreferencesScreen({required this.initialValues});

  final Map<String, dynamic> initialValues;

  @override
  State<_ApplicationPreferencesScreen> createState() =>
      _ApplicationPreferencesScreenState();
}

class _ApplicationPreferencesScreenState
    extends State<_ApplicationPreferencesScreen> {
  late final Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Application',
      subtitle: 'Ajustez le comportement du manager app a votre rythme.',
      heroIcon: LucideIcons.settings,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Langue preferee',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageChoiceChip(
                        label: 'Francais',
                        isActive: (_values['language'] as String?) != 'en',
                        onTap: () => setState(() => _values['language'] = 'fr'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LanguageChoiceChip(
                        label: 'English',
                        isActive: (_values['language'] as String?) == 'en',
                        onTap: () => setState(() => _values['language'] = 'en'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ToggleCard(
            icon: LucideIcons.refreshCcw,
            title: 'Auto rafraichir les agents',
            subtitle:
                'Actualiser les cartes d agents plus vite quand vous restez sur la page.',
            value: _values['autoRefreshAgents'] == true,
            onChanged: (value) {
              setState(() => _values['autoRefreshAgents'] = value);
            },
          ),
          const SizedBox(height: 10),
          _ToggleCard(
            icon: LucideIcons.layoutGrid,
            title: 'Mode cartes compactes',
            subtitle:
                'Preferer un affichage manager plus dense pour voir plus d agents.',
            value: _values['compactCards'] == true,
            onChanged: (value) {
              setState(() => _values['compactCards'] = value);
            },
          ),
          const SizedBox(height: 18),
          _PrimaryActionButton(
            label: 'Enregistrer',
            onTap: () => Navigator.pop(context, _values),
          ),
        ],
      ),
    );
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.subtitle,
    required this.heroIcon,
    required this.body,
  });

  final String title;
  final String subtitle;
  final IconData heroIcon;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          SizedBox(
            height: 220,
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
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.94),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _CircleBtn(
                              icon: LucideIcons.arrowLeft,
                              onTap: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.30),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kAuthGold.withValues(alpha: 0.50),
                                ),
                              ),
                              child: Icon(
                                heroIcon,
                                color: kAuthGold,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      color:
                                          Colors.white.withValues(alpha: 0.65),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(
                color: kAuthGold.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, color: kAuthGold, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: Colors.black,
            activeTrackColor: const Color(0xFF22C55E),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LanguageChoiceChip extends StatelessWidget {
  const _LanguageChoiceChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? kAuthGold : _kMutedCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? kAuthGold : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isActive ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleAddressPickerSheet extends StatefulWidget {
  const _GoogleAddressPickerSheet({
    required this.title,
    required this.apiKey,
    required this.initialValue,
  });

  final String title;
  final String apiKey;
  final String initialValue;

  @override
  State<_GoogleAddressPickerSheet> createState() =>
      _GoogleAddressPickerSheetState();
}

class _GoogleAddressPickerSheetState extends State<_GoogleAddressPickerSheet> {
  late final TextEditingController _controller;
  final List<String> _results = <String>[];
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    if (widget.initialValue.trim().length >= 3) {
      _search(widget.initialValue.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String query) async {
    if (query.length < 3) {
      if (!mounted) return;
      setState(() {
        _results.clear();
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        <String, String>{
          'input': query,
          'key': widget.apiKey,
          'language': 'fr',
          'types': 'address',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('autocomplete failed');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = (body['predictions'] as List<dynamic>? ?? <dynamic>[])
          .map((entry) => entry as Map<String, dynamic>)
          .map((entry) => (entry['description'] as String?)?.trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(predictions);
      });
    } catch (error) {
      debugPrint('Address autocomplete error: $error');
      if (!mounted) return;
      setState(() => _results.clear());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(title: widget.title),
            const SizedBox(height: 16),
            _GoldInput(
              controller: _controller,
              label: 'Rechercher une adresse',
              icon: LucideIcons.search,
              onChanged: _onChanged,
            ),
            const SizedBox(height: 14),
            if (_controller.text.trim().isNotEmpty)
              GestureDetector(
                onTap: () => Navigator.pop(context, _controller.text.trim()),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _kMutedCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.checkCircle2,
                        color: kAuthGold,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Utiliser: ${_controller.text.trim()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_controller.text.trim().isNotEmpty) const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBorder),
                ),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: kAuthGold,
                          strokeWidth: 2,
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Tapez une adresse pour voir les suggestions Google.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(10),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final suggestion = _results[index];
                              return InkWell(
                                onTap: () => Navigator.pop(context, suggestion),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _kMutedCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        LucideIcons.mapPin,
                                        color: kAuthGold,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          suggestion,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        LucideIcons.chevronRight,
                                        color: Colors.white
                                            .withValues(alpha: 0.30),
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GoldInput extends StatelessWidget {
  const _GoldInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.55),
        ),
        prefixIcon: Icon(icon, color: kAuthGold, size: 18),
        filled: true,
        fillColor: _kMutedCard,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: kAuthGold.withValues(alpha: 0.80)),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAuthGold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

String _resolveDisplayName(User firebaseUser, Map<String, dynamic> userData) {
  final firstName = ((userData['firstName'] as String?) ?? '').trim();
  final lastName = ((userData['lastName'] as String?) ?? '').trim();
  final username = ((userData['username'] as String?) ?? '').trim();
  final composed =
      [firstName, lastName].where((value) => value.isNotEmpty).join(' ').trim();
  if (composed.isNotEmpty) return composed;
  if (username.isNotEmpty) return username;
  if ((firebaseUser.displayName ?? '').trim().isNotEmpty) {
    return firebaseUser.displayName!.trim();
  }
  return 'Gestionnaire';
}

String _formatMemberSince(dynamic createdAt, User firebaseUser) {
  DateTime? date;
  if (createdAt is Timestamp) {
    date = createdAt.toDate();
  } else {
    date = firebaseUser.metadata.creationTime;
  }
  if (date == null) return 'Non renseigne';
  const months = <String>[
    'Jan',
    'Fev',
    'Mar',
    'Avr',
    'Mai',
    'Jun',
    'Jul',
    'Aou',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

Uint8List? _decodeBase64Photo(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return base64Decode(raw.trim());
  } catch (_) {
    return null;
  }
}

String _initials(String input) {
  final parts = input
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'G';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

Map<String, dynamic> _notificationPrefs(Map<String, dynamic> userData) {
  final raw =
      ((userData['managerPreferences'] as Map?)?['notifications'] as Map?)
          ?.cast<String, dynamic>();
  return <String, dynamic>{
    'messages': true,
    'agentAvailability': true,
    'offerUpdates': true,
    'dailySummary': false,
    ...?raw,
  };
}

Map<String, dynamic> _privacyPrefs(Map<String, dynamic> userData) {
  final raw = ((userData['managerPreferences'] as Map?)?['privacy'] as Map?)
      ?.cast<String, dynamic>();
  return <String, dynamic>{
    'shareManagerName': true,
    'shareExactCondoAddress': false,
    'sharePhoneWithSelectedAgents': true,
    'showOnlyTermsAcceptedWorkers': true,
    'requireCvBeforeSelection': true,
    ...?raw,
  };
}

Map<String, dynamic> _securityPrefs(Map<String, dynamic> userData) {
  final raw = ((userData['managerPreferences'] as Map?)?['security'] as Map?)
      ?.cast<String, dynamic>();
  return <String, dynamic>{
    'biometricLock': true,
    'loginAlerts': true,
    'sensitiveDataShield': true,
    ...?raw,
  };
}

Map<String, dynamic> _applicationPrefs(Map<String, dynamic> userData) {
  final raw = ((userData['managerPreferences'] as Map?)?['application'] as Map?)
      ?.cast<String, dynamic>();
  return <String, dynamic>{
    'language': 'fr',
    'autoRefreshAgents': true,
    'compactCards': false,
    ...?raw,
  };
}

Future<String> _readMapsKey() async {
  try {
    final rawEnv = await rootBundle.loadString('.env');
    for (final line in rawEnv.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separatorIndex =
          trimmed.contains('=') ? trimmed.indexOf('=') : trimmed.indexOf(':');
      if (separatorIndex <= 0) continue;
      final key = trimmed.substring(0, separatorIndex).trim();
      if (key != 'GOOGLE_MAPS_API_KEY') continue;
      final value = trimmed.substring(separatorIndex + 1).trim();
      if (value.isNotEmpty) return value;
    }
  } catch (_) {}
  return _kFallbackMapsKey;
}

String _flagEmoji(String countryCode) {
  return countryCode
      .toUpperCase()
      .codeUnits
      .map((unit) => String.fromCharCode(unit + 127397))
      .join();
}

class _MediaOptionTile extends StatelessWidget {
  const _MediaOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kMutedCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.14),
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
          ],
        ),
      ),
    );
  }
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
