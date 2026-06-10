import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:stayfix/screens/auth_screen.dart';
import 'package:stayfix/screens/intervenant_profile_screen.dart';
import 'package:stayfix/screens/manager_chat_thread_screen.dart';
import 'package:stayfix/screens/manager_messages_screen.dart';
import 'package:stayfix/screens/manager_notifications_screen.dart';
import 'package:stayfix/screens/manager_offers_screen.dart';
import 'package:stayfix/screens/manager_property_route_helper.dart';
import 'package:stayfix/services/app_session_service.dart';
import 'package:stayfix/services/manager_worker_contact_service.dart';
import 'package:stayfix/services/property_scope_service.dart';
import 'package:stayfix/widgets/unread_messages_nav_item.dart';
import 'package:lucide_icons/lucide_icons.dart';

// -- Google Maps API key -------------------------------------------------------
const _kFallbackMapsKey = '';

// -- Dark-gold UI constants ----------------------------------------------------
const kDarkCard = Color(0xFF141414);
const kDarkBorder = Color(0xFF252525);
const kWhite70 = Color(0xB3FFFFFF);
const kWhite40 = Color(0x66FFFFFF);
const kOrangeDot = Color(0xFFFF6B35);
const kGreenDot = Color(0xFF22C55E);
const List<String> _kAllWorkerDepartments = <String>[
  'Propose au menage',
  'Maintenance generale',
  'Main-d\'oeuvre qualifiee',
];
final Map<String, _LatLng?> _geocodeCache = <String, _LatLng?>{};

// -- Sort enum (unchanged) -----------------------------------------------------
enum WorkerSortBy {
  relevance('Pertinence'),
  distance('Distance'),
  experience('Experience'),
  rating('Note'),
  availability('Disponibilite');

  const WorkerSortBy(this.label);
  final String label;
}

// -- Filter state (unchanged) --------------------------------------------------
class WorkerFilterState {
  const WorkerFilterState({
    this.department,
    this.role,
    this.specialty,
    this.experience = 5,
    this.maxDistanceKm = 20,
    this.availableNow = false,
    this.availabilityDate,
  });

  final String? department;
  final String? role;
  final String? specialty;
  final double experience;
  final double maxDistanceKm;
  final bool availableNow;
  final DateTime? availabilityDate;

  WorkerFilterState copyWith({
    String? department,
    bool clearDepartment = false,
    String? role,
    bool clearRole = false,
    String? specialty,
    bool clearSpecialty = false,
    double? experience,
    double? maxDistanceKm,
    bool? availableNow,
    DateTime? availabilityDate,
    bool clearAvailabilityDate = false,
  }) {
    return WorkerFilterState(
      department: clearDepartment ? null : (department ?? this.department),
      role: clearRole ? null : (role ?? this.role),
      specialty: clearSpecialty ? null : (specialty ?? this.specialty),
      experience: experience ?? this.experience,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      availableNow: availableNow ?? this.availableNow,
      availabilityDate: clearAvailabilityDate
          ? null
          : (availabilityDate ?? this.availabilityDate),
    );
  }
}

// -- Screen widget (unchanged) -------------------------------------------------
class IntervenantsScreen extends StatefulWidget {
  const IntervenantsScreen({super.key});

  @override
  State<IntervenantsScreen> createState() => _IntervenantsScreenState();
}

// -------------------------------------------------------------------------------
// Screen state — UI layer rewritten, data layer intact
// -------------------------------------------------------------------------------
class _IntervenantsScreenState extends State<IntervenantsScreen> {
  // -- Data state (unchanged) --
  final WorkerSortBy _sortBy = WorkerSortBy.relevance;
  WorkerFilterState _filters = const WorkerFilterState();
  Future<_WorkersPageData>? _workersFuture;

  // -- New UI state --
  String? _selectedDepartment;
  String? _expandedWorkerId;
  double _radiusKm = 12.0;
  String? _managerAddressOverride;
  _LatLng? _managerCoordsOverride;
  bool _isResolvingManagerAddress = false;
  bool _hasCompletedInitialLocationAttempt = false;

  String get _activeUid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  @override
  void initState() {
    super.initState();
    _restoreAvailabilityPreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncManagerCurrentAddress();
    });
  }

  Future<void> _restoreAvailabilityPreference() async {
    final uid = _activeUid;
    if (uid.isEmpty) return;
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final value = ((data['managerPreferences'] as Map?)?['intervenants']
          as Map?)?['availableTodayOnly'];
      if (value is bool && mounted) {
        setState(() {
          _filters = _filters.copyWith(availableNow: value);
        });
      }
    } catch (_) {}
  }

  Future<void> _persistAvailabilityPreference(bool value) async {
    final uid = _activeUid;
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'managerPreferences': {
          'intervenants': {
            'availableTodayOnly': value,
          },
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // -----------------------------------------------------------------------------
  // Data loading (unchanged)
  // -----------------------------------------------------------------------------

  Future<_WorkersPageData> _loadData(String uid) async {
    final mapsKey = await _readMapsKey();
    final userSnapshot =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userSnapshot.data() ?? const <String, dynamic>{};
    final accountType =
        (userData['accountType'] as String?)?.trim().toLowerCase();
    final assignedPropertyIds = PropertyScopeService.scopedPropertyIds(userData);

    final List<DocumentSnapshot<Map<String, dynamic>>> propertyDocs;
    if (accountType == 'manager' || accountType == 'concierge') {
      propertyDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final propertyId in assignedPropertyIds) {
        final doc = await FirebaseFirestore.instance
            .collection('hotels')
            .doc(propertyId)
            .get();
        if (doc.exists) {
          propertyDocs.add(doc);
        }
      }
    } else {
      final propertySnapshot = await FirebaseFirestore.instance
          .collection('hotels')
          .where('ownerId', isEqualTo: uid)
          .limit(12)
          .get();
      propertyDocs = propertySnapshot.docs;
    }

    _PropertyInfo? property;
    _LatLng? managerCoords;
    List<_WorkerItem> workers = const [];

    if (propertyDocs.isNotEmpty) {
      var propertyDoc = propertyDocs.first;
      for (final doc in propertyDocs) {
        if ((doc.data()?['location'] as String?)?.trim().isNotEmpty ?? false) {
          propertyDoc = doc;
          break;
        }
      }
      final propertyData = propertyDoc.data() ?? const <String, dynamic>{};
      property = _PropertyInfo(
        id: propertyDoc.id,
        name: (propertyData['name'] as String?)?.trim(),
        address: (propertyData['location'] as String?)?.trim(),
      );
      if (_managerCoordsOverride != null) {
        managerCoords = _managerCoordsOverride;
      } else if (property.address != null && property.address!.isNotEmpty) {
        managerCoords =
            await _geocodeAddress(property.address!, apiKey: mapsKey);
      }
    } else if (_managerCoordsOverride != null) {
      managerCoords = _managerCoordsOverride;
    }

    if (!_hasCompletedInitialLocationAttempt && managerCoords == null) {
      return _WorkersPageData(
        property: property,
        workers: const [],
        allWorkers: const [],
        departments: const [],
        roleOptions: const [],
        specialtyOptions: const [],
        propertyAddressDefined:
            (_managerAddressOverride?.trim().isNotEmpty ?? false) ||
                (property?.address != null && property!.address!.isNotEmpty),
        distanceFilteringSupported: false,
        locationPending: true,
      );
    }

    final workerSnapshot =
        await FirebaseFirestore.instance.collection('profiles').get();

    final resolved = await Future.wait(
      workerSnapshot.docs
          .where((doc) => _isStayFixJobWorkerProfile(doc.data()))
          .map((doc) async {
        double? distanceKm;
        if (managerCoords != null) {
          final addr = (_resolveWorkerAddress(doc.data()) ?? '').trim();
          if (addr.isNotEmpty) {
            final coords = await _geocodeAddress(addr, apiKey: mapsKey);
            if (coords != null) {
              distanceKm = _haversineKm(managerCoords, coords);
            }
          }
        }
        return _workerFromDoc(doc, distanceKm: distanceKm);
      }),
    );
    workers = resolved
        .where((worker) => worker.fullName.trim().isNotEmpty)
        .toList();

    final departments = _buildDepartmentOptions(workers);
    final filteredWorkers = _applyFiltersAndSort(workers, _filters, _sortBy);

    return _WorkersPageData(
      property: property,
      workers: filteredWorkers,
      allWorkers: workers,
      departments: departments,
      roleOptions: _buildRoleOptions(workers, _filters.department),
      specialtyOptions: _buildSpecialtyOptions(workers, _filters.role),
      propertyAddressDefined:
          (_managerAddressOverride?.trim().isNotEmpty ?? false) ||
              (property?.address != null && property!.address!.isNotEmpty),
      distanceFilteringSupported: false,
      locationPending: false,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final uid = _activeUid;
    if (uid.isEmpty) return;
    setState(() {
      _workersFuture = _loadData(uid);
    });
  }

  void _showSoonMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kDarkCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _openWorkerConversation(
    _WorkerItem worker, {
    required bool sendSelectionMessage,
  }) async {
    try {
      final handle = await ManagerWorkerContactService.openConversation(
        workerId: worker.id,
        workerName: worker.fullName,
        workerRole: worker.role,
        workerDepartment: worker.displayHeadline,
        workerPhotoBase64: worker.photoBase64,
        isWorkerAvailable: worker.isAvailableNow,
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
              backgroundColor: kDarkCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Intervenant bloque',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Text(
                'Vous avez bloque cet intervenant. Voulez-vous le debloquer ?',
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.80),
                  height: 1.4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Annuler',
                    style: GoogleFonts.manrope(color: Colors.white70),
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
      await ManagerWorkerContactService.unblockWorker(workerId: worker.id);
      if (!mounted) return;
      _showSoonMessage('Intervenant debloque.');
    } catch (_) {
      if (!mounted) return;
      _showSoonMessage(
          'Impossible d ouvrir cette conversation pour le moment.');
    }
  }

  Future<void> _openProfileScreen() async {
    final uid = _activeUid;
    if (uid.isEmpty || !mounted) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final propertyType =
        (doc.data()?['propertyProfileType'] as String?)?.trim() ?? '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => buildManagerProfileScreen(
          propertyType: propertyType,
        ),
      ),
    );
  }

  Future<void> _syncManagerCurrentAddress() async {
    if (_isResolvingManagerAddress) return;
    setState(() {
      _isResolvingManagerAddress = true;
      _managerAddressOverride ??= 'Recherche de votre position...';
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _managerAddressOverride = 'Activez votre localisation';
          });
        }
        _showSoonMessage(
          'Activez la localisation pour utiliser votre position actuelle.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _managerAddressOverride = 'Touchez pour autoriser la localisation';
          });
        }
        _showSoonMessage(
          'Autorisez la localisation pour afficher les agents proches.',
        );
        return;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _managerCoordsOverride =
              _LatLng(lastKnown.latitude, lastKnown.longitude);
          _managerAddressOverride ??= 'Position actuelle detectee';
          final uid = _activeUid;
          if (uid.isNotEmpty) {
            _workersFuture = _loadData(uid);
          }
        });
      }

      Position? position = lastKnown;
      try {
        final currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        position = currentPosition;
      } catch (_) {
        position ??= await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        if (mounted) {
          setState(() {
            _managerAddressOverride =
                'Touchez pour utiliser votre position actuelle';
          });
        }
        _showSoonMessage(
          "Aucune position disponible. Sur l'emulateur Android, definissez une position GPS dans Extended controls > Location.",
        );
        return;
      }
      final resolvedPosition = position;

      final mapsKey = await _readMapsKey();
      final exactAddress = await _reverseGeocode(
        lat: resolvedPosition.latitude,
        lng: resolvedPosition.longitude,
        apiKey: mapsKey,
      );
      if (!mounted) return;

      setState(() {
        _managerCoordsOverride = _LatLng(
          resolvedPosition.latitude,
          resolvedPosition.longitude,
        );
        _managerAddressOverride = exactAddress ??
            '${resolvedPosition.latitude.toStringAsFixed(6)}, ${resolvedPosition.longitude.toStringAsFixed(6)}';
        final uid = _activeUid;
        if (uid.isNotEmpty) {
          _workersFuture = _loadData(uid);
        }
      });
    } catch (error, stackTrace) {
      developer.log(
        'Unable to resolve manager current address',
        name: 'IntervenantsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _managerAddressOverride = _managerCoordsOverride != null
              ? _managerAddressOverride
              : 'Touchez pour utiliser votre position actuelle';
        });
        _showSoonMessage(
          'Impossible de recuperer votre position actuelle: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingManagerAddress = false;
          _hasCompletedInitialLocationAttempt = true;
          final uid = _activeUid;
          if (uid.isNotEmpty) {
            _workersFuture ??= _loadData(uid);
          }
        });
      }
    }
  }

  Future<void> _openFilterSheet(_WorkersPageData data) async {
    final result = await showModalBottomSheet<WorkerFilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkersFilterSheet(
        initialState: _filters,
        departments: data.departments,
        roleOptions: data.roleOptions,
        specialtyOptions: data.specialtyOptions,
        propertyAddressDefined: data.propertyAddressDefined,
        distanceFilteringSupported: data.distanceFilteringSupported,
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _filters = result;
      _selectedDepartment = result.department;
      _radiusKm = result.maxDistanceKm;
    });
  }

  // -----------------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final activeUid = _activeUid;
    if (activeUid.isEmpty) return const AuthScreen();

    final mq = MediaQuery.of(context);
    final heroHeight = (mq.size.height * 0.30).clamp(200.0, 260.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      bottomNavigationBar: _buildBottomNavBar(),
      body: FutureBuilder<_WorkersPageData>(
        future: _workersFuture ??= _loadData(activeUid),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final isLoading = snapshot.connectionState != ConnectionState.done ||
              (data?.locationPending ?? false);
          final hasError = snapshot.hasError;
          final workers = data?.workers ?? const [];

          return Column(
            children: [
              // -- Hero ----------------------------------------------------
              SizedBox(
                height: heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/interventfilterheroimg.webp',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFF0A0A0A)),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 0.45, 1.0],
                          colors: [
                            Color(0x55000000),
                            Color(0x33000000),
                            Color(0xDD000000),
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
                                _HeroRoundButton(
                                  icon: LucideIcons.arrowLeft,
                                  onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => buildManagerHomeScreen(),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                const SizedBox.shrink(),
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _HeroRoundButton(
                                      icon: LucideIcons.bell,
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ManagerNotificationsScreen(),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 5,
                                      right: 5,
                                      child: Container(
                                        width: 9,
                                        height: 9,
                                        decoration: const BoxDecoration(
                                          color: kOrangeDot,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Title block
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Intervenants',
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    height: 1.0,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Trouvez le bon professionnel pour votre besoin',
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
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

              // -- Department chips -----------------------------------------
              SizedBox(
                height: 60,
                child: _buildDepartmentChips(data),
              ),

              // -- Filter block ---------------------------------------------
              _buildFilterBlock(data),

              // -- Worker list ----------------------------------------------
              Expanded(
                child: _buildWorkerList(workers, isLoading, hasError, data),
              ),
            ],
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // Department chips
  // -----------------------------------------------------------------------------

  Widget _buildDepartmentChips(_WorkersPageData? data) {
    final departments = data?.departments ?? const [];
    final allLabels = <String>['Tout', ...departments];

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: allLabels.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final label = allLabels[index];
        final isAll = label == 'Tout';
        final isActive =
            isAll ? _selectedDepartment == null : _selectedDepartment == label;
        return _DepartmentChip(
          label: label,
          icon: _departmentIcon(label),
          isActive: isActive,
          onTap: () {
            setState(() {
              if (isAll) {
                _selectedDepartment = null;
                _filters = _filters.copyWith(clearDepartment: true);
              } else {
                _selectedDepartment = label;
                _filters = _filters.copyWith(
                  department: label,
                  clearRole: true,
                  clearSpecialty: true,
                );
              }
            });
          },
        );
      },
    );
  }

  IconData _departmentIcon(String label) {
    final lower = label.toLowerCase();
    if (lower == 'tout') return LucideIcons.layoutGrid;
    if (lower.contains('maintenance')) return LucideIcons.wrench;
    if (lower.contains('qualifi')) return LucideIcons.hammer;
    if (lower.contains('chambre') || lower.contains('prepos')) {
      return LucideIcons.bed;
    }
    if (lower.contains('houseman')) return LucideIcons.building;
    if (lower.contains('concierge')) return LucideIcons.key;
    if (lower.contains('menage') || lower.contains('ménage')) {
      return LucideIcons.sparkles;
    }
    return LucideIcons.briefcase;
  }

  // -----------------------------------------------------------------------------
  // Filter block
  // -----------------------------------------------------------------------------

  Widget _buildFilterBlock(_WorkersPageData? data) {
    final managerAddress = _managerAddressOverride ??
        data?.property?.address ??
        data?.property?.name;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAuthGold.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Address dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Adresse',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _syncManagerCurrentAddress,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              color: kAuthGold.withValues(alpha: 0.90),
                              size: 13,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _isResolvingManagerAddress
                                    ? 'Localisation en cours...'
                                    : managerAddress?.trim().isNotEmpty == true
                                        ? managerAddress!
                                        : 'Utiliser ma position actuelle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              LucideIcons.crosshair,
                              color: kAuthGold.withValues(alpha: 0.80),
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Radius slider
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Rayon',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_radiusKm.round()} km',
                          style: GoogleFonts.inter(
                            color: kAuthGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 36,
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: kAuthGold,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.12),
                          thumbColor: kAuthGold,
                          overlayColor: kAuthGold.withValues(alpha: 0.15),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 11),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 20),
                        ),
                        child: Slider(
                          value: _radiusKm,
                          min: 5,
                          max: 20,
                          divisions: 15,
                          onChanged: (v) => setState(() {
                            _radiusKm = v;
                            _filters = _filters.copyWith(maxDistanceKm: v);
                          }),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: ['5 km', '10 km', '15 km', '20 km']
                            .map((t) => Text(
                                  t,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.70),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
              color: Colors.white.withValues(alpha: 0.08),
              height: 1,
              thickness: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.calendarCheck,
                  color: kAuthGold.withValues(alpha: 0.85), size: 15),
              const SizedBox(width: 9),
              Text(
                'Disponibles aujourd\'hui',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerRight,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    switchTheme: SwitchThemeData(
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return kGreenDot.withValues(alpha: 0.45);
                        }
                        return const Color(0xFF3A3A3A);
                      }),
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return kGreenDot;
                        }
                        return const Color(0xFF888888);
                      }),
                    ),
                  ),
                  child: Switch(
                    value: _filters.availableNow,
                    activeTrackColor: const Color(0xFF22C55E),
                    activeThumbColor: Colors.white,
                    onChanged: (v) {
                      setState(
                        () => _filters = _filters.copyWith(availableNow: v),
                      );
                      _persistAvailabilityPreference(v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // Worker list
  // -----------------------------------------------------------------------------

  Widget _buildWorkerList(
    List<_WorkerItem> workers,
    bool isLoading,
    bool hasError,
    _WorkersPageData? data,
  ) {
    if (isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        itemCount: 4,
        itemBuilder: (context, index) {
          return const _WorkerCardSkeleton();
        },
      );
    }

    if (hasError) {
      return _WorkersErrorCard(onRetry: _refresh);
    }

    if (workers.isEmpty) {
      return _WorkersEmptyCard(
        onModifyFilters: data == null ? _refresh : () => _openFilterSheet(data),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: workers.length,
      itemBuilder: (context, index) {
        final worker = workers[index];
        final isExpanded = _expandedWorkerId == worker.id;
        return _CompactWorkerCard(
          worker: worker,
          isExpanded: isExpanded,
          onToggle: () => setState(() {
            _expandedWorkerId = isExpanded ? null : worker.id;
          }),
          onProfileTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IntervenantProfileScreen(workerId: worker.id),
            ),
          ),
          onSelectTap: () => _openWorkerConversation(
            worker,
            sendSelectionMessage: true,
          ),
        );
      },
    );
  }

  // -----------------------------------------------------------------------------
  // Bottom nav bar
  // -----------------------------------------------------------------------------

  Widget _buildBottomNavBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
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
                MaterialPageRoute(builder: (_) => buildManagerHomeScreen()),
              ),
            ),
            const _NavItem(
              icon: LucideIcons.users,
              label: 'Agents',
              isActive: true,
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
              inactiveColor: Colors.white.withValues(alpha: 0.65),
              dotColor: const Color(0xFFFF3B30),
            ),
            _NavItem(
              icon: LucideIcons.user,
              label: 'Profil',
              isActive: false,
              onTap: _openProfileScreen,
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------
// Data layer — completely unchanged
// -------------------------------------------------------------------------------

_WorkerItem _workerFromDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc, {
  double? distanceKm,
}) {
  final data = doc.data();
  final fullNameField = ((data['fullName'] as String?) ?? '').trim();
  final displayNameField = ((data['displayName'] as String?) ?? '').trim();
  final firstName = ((data['firstName'] as String?) ?? '').trim();
  final lastName = ((data['lastName'] as String?) ?? '').trim();
  final username = ((data['username'] as String?) ?? '').trim();
  final email = ((data['email'] as String?) ?? '').trim();
  final role = ((data['role'] as String?) ?? '').trim();
  final department = ((data['department'] as String?) ?? '').trim();
  final jobTitle = ((data['jobTitle'] as String?) ?? '').trim();
  final maintenanceType = ((data['maintenanceType'] as String?) ?? '').trim();
  final profileImageUrl = _resolveWorkerProfileImage(data);
  final specialty = ((data['specialty'] as String?) ?? '').trim();
  final speciality = ((data['speciality'] as String?) ?? '').trim();
  final specialtyFromList = () {
    final list = data['specialties'];
    if (list is List) {
      for (final item in list) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }();
  final rating = (data['rating'] as num?)?.toDouble();
  final experience = (data['experienceYears'] as num?)?.toDouble();
  final verified = data['verified'] == true || data['isVerified'] == true;
  final availableNow = _isWorkerAvailableNow(data);
  final availabilityLabel = _resolveAvailabilityLabel(data);
  final address = (_resolveWorkerAddress(data) ?? '').trim();
  final photoBase64 = _resolveWorkerPhotoBase64(data);

  final fullName = '$firstName $lastName'.trim();
  final displayName = fullNameField.isNotEmpty
      ? fullNameField
      : displayNameField.isNotEmpty
          ? displayNameField
          : fullName.isNotEmpty
              ? fullName
              : (username.isNotEmpty
                  ? username
                  : (email.isNotEmpty
                      ? email.split('@').first
                      : 'Intervenant'));

  final resolvedRole = _resolveWorkerRole(
    role: role,
    jobTitle: jobTitle,
    department: department,
    maintenanceType: maintenanceType,
  );
  final resolvedSpecialty = _resolveWorkerSpecialty(
    specialty: specialty,
    speciality: speciality,
    specialtyFromList: specialtyFromList,
    maintenanceType: maintenanceType,
  );
  final resolvedDepartment = _resolveWorkerDepartment(
    department: department,
    role: resolvedRole,
  );
  final displayHeadline = _resolveWorkerDisplayHeadline(
    department: resolvedDepartment,
    specialty: resolvedSpecialty,
    fallbackRole: resolvedRole,
  );
  final resolvedExperience = experience ?? _parseExperienceYears(data);

  return _WorkerItem(
    id: doc.id,
    fullName: displayName,
    role: resolvedRole,
    department: resolvedDepartment,
    specialty: resolvedSpecialty,
    displayHeadline: displayHeadline,
    profileImageUrl: profileImageUrl,
    photoBase64: photoBase64,
    isVerified: verified,
    isAvailableNow: availableNow,
    availabilityLabel: availabilityLabel,
    availabilitySlots: _parseAvailabilitySlots(data),
    experienceYears: resolvedExperience,
    rating: rating,
    address: address.isNotEmpty ? address : null,
    distanceKm: distanceKm,
  );
}

bool _isStayFixJobWorkerProfile(Map<String, dynamic> data) {
  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  if (status == 'deleted' || status == 'disabled' || status == 'archived') {
    return false;
  }

  final appAccess = (data['appAccess'] as String?)?.trim().toLowerCase();
  if (appAccess == 'stayfix_job') {
    return true;
  }

  final accountType = (data['accountType'] as String?)?.trim().toLowerCase();
  if (accountType == 'worker' || accountType == 'concierge') {
    return true;
  }

  final department = (data['department'] as String?)?.trim() ?? '';
  final role = (data['role'] as String?)?.trim().toLowerCase() ?? '';
  final specialties = data['specialties'];
  if (department.isNotEmpty) {
    return true;
  }
  if (specialties is List && specialties.isNotEmpty) {
    return true;
  }
  return role.isNotEmpty &&
      !role.contains('manager') &&
      !role.contains('gestionnaire') &&
      !role.contains('director');
}

String? _resolveWorkerProfileImage(Map<String, dynamic> data) {
  const candidateKeys = [
    'photoUrl',
    'profilePhoto',
    'profileImageUrl',
    'profileImage',
    'avatarUrl',
    'avatar',
    'imageUrl',
    'image',
    'photo',
    'photoURL',
    'picture',
  ];

  for (final key in candidateKeys) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  final nestedProfile = data['profile'];
  if (nestedProfile is Map) {
    for (final key in candidateKeys) {
      final value = (nestedProfile[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  return null;
}

String? _resolveWorkerPhotoBase64(Map<String, dynamic> data) {
  const candidateKeys = [
    'photoBase64',
    'profilePhotoBase64',
    'imageBase64',
    'avatarBase64',
  ];

  for (final key in candidateKeys) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  final nestedProfile = data['profile'];
  if (nestedProfile is Map) {
    for (final key in candidateKeys) {
      final value = (nestedProfile[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  return null;
}

List<String> _buildDepartmentOptions(List<_WorkerItem> workers) {
  final options = <String>{
    ..._kAllWorkerDepartments,
    ...workers
        .map((worker) => worker.department)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
  }.toList()
    ..sort((a, b) {
      const priority = <String, int>{
        'Propose au menage': 0,
        'Maintenance generale': 1,
        "Main-d'oeuvre qualifiee": 2,
      };
      final orderA = priority[a] ?? 99;
      final orderB = priority[b] ?? 99;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      return a.compareTo(b);
    });
  return options;
}

List<String> _buildRoleOptions(List<_WorkerItem> workers, String? department) {
  final scoped = department == null
      ? workers
      : workers.where(
          (worker) => _matchesWorkerDepartment(worker, department),
        );
  final options = scoped
      .map((worker) => worker.role)
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return options;
}

List<String> _buildSpecialtyOptions(List<_WorkerItem> workers, String? role) {
  final scoped = role == null
      ? workers
      : workers.where(
          (worker) => _matchesNormalizedValue(worker.role, role),
        );
  final options = scoped
      .map((worker) => worker.specialty)
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return options;
}

List<_WorkerItem> _applyFiltersAndSort(
  List<_WorkerItem> workers,
  WorkerFilterState filters,
  WorkerSortBy sortBy,
) {
  final filtered = workers.where((worker) {
    if (worker.distanceKm == null) {
      return false;
    }
    if (filters.department != null &&
        !_matchesWorkerDepartment(worker, filters.department!)) {
      return false;
    }
    if (filters.role != null &&
        !_matchesNormalizedValue(worker.role, filters.role!)) {
      return false;
    }
    if (filters.specialty != null &&
        !_matchesNormalizedValue(worker.specialty, filters.specialty!)) {
      return false;
    }
    if (filters.availableNow && !worker.isAvailableNow) {
      return false;
    }
    if (worker.distanceKm != null &&
        worker.distanceKm! > filters.maxDistanceKm) {
      return false;
    }
    if (worker.experienceYears != null &&
        worker.experienceYears! < filters.experience) {
      return false;
    }
    return true;
  }).toList();

  filtered.sort((a, b) {
    switch (sortBy) {
      case WorkerSortBy.experience:
        return (b.experienceYears ?? -1).compareTo(a.experienceYears ?? -1);
      case WorkerSortBy.rating:
        return (b.rating ?? -1).compareTo(a.rating ?? -1);
      case WorkerSortBy.availability:
        return (b.isAvailableNow ? 1 : 0).compareTo(a.isAvailableNow ? 1 : 0);
      case WorkerSortBy.distance:
        return (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity);
      case WorkerSortBy.relevance:
        return a.fullName.compareTo(b.fullName);
    }
  });

  return filtered;
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

int? _slotMinutes({
  required int? hour,
  required int? minute,
  required String? period,
}) {
  if (hour == null) return null;
  final normalizedMinute = (minute ?? 0).clamp(0, 59);
  final normalizedPeriod = (period ?? '').trim().toUpperCase();
  if (normalizedPeriod == 'AM' || normalizedPeriod == 'PM') {
    var normalizedHour = hour % 12;
    if (normalizedPeriod == 'PM') normalizedHour += 12;
    return normalizedHour * 60 + normalizedMinute;
  }
  if (hour < 0 || hour > 23) return null;
  return hour * 60 + normalizedMinute;
}

String? _resolveAvailabilityLabel(Map<String, dynamic> data) {
  final directLabel = ((data['availabilityLabel'] as String?) ?? '').trim();
  if (directLabel.isNotEmpty) return directLabel;
  final slots = data['availabilitySlots'];
  if (slots is List && slots.isNotEmpty) {
    final firstSlot = slots.first;
    if (firstSlot is Map<String, dynamic>) {
      final label = ((firstSlot['label'] as String?) ?? '').trim();
      if (label.isNotEmpty) return label;
    }
    if (firstSlot is Map) {
      final label = (firstSlot['label']?.toString() ?? '').trim();
      if (label.isNotEmpty) return label;
    }
  }
  return null;
}

double? _parseExperienceYears(Map<String, dynamic> data) {
  final directValue = data['experienceYears'];
  if (directValue is num) return directValue.toDouble();
  final departmentValue = data['departmentExperienceYears'];
  if (departmentValue is num) return departmentValue.toDouble();
  final fallback = data['experience'];
  if (fallback is num) return fallback.toDouble();
  if (fallback is String) {
    return double.tryParse(fallback.replaceAll(RegExp(r'[^0-9.]'), ''));
  }
  return null;
}

String? _resolveWorkerAddress(Map<String, dynamic> data) {
  const candidateKeys = [
    'address',
    'jobAddress',
    'location',
    'currentAddress',
  ];

  for (final key in candidateKeys) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  final nestedProfile = data['profile'];
  if (nestedProfile is Map) {
    for (final key in candidateKeys) {
      final value = (nestedProfile[key]?.toString() ?? '').trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }

  return null;
}

List<String> _parseAvailabilitySlots(Map<String, dynamic> data) {
  final slots = data['availabilitySlots'];
  if (slots is! List || slots.isEmpty) return const [];
  final normalizedSlots = slots.whereType<Map>().toList();
  if (normalizedSlots.isEmpty) return const [];

  final allWeekAlwaysAvailable = normalizedSlots.length >= 7 &&
      normalizedSlots.every(_isAlwaysAvailableSlot) &&
      normalizedSlots
              .map((slot) => (slot['weekday'] as num?)?.toInt())
              .whereType<int>()
              .toSet()
              .length >=
          7;
  if (allWeekAlwaysAvailable) {
    return const ['Tous les jours • Toujours disponible'];
  }

  final result = <String>[];
  for (final slot in normalizedSlots) {
    final dayLabel = _weekdayLabel((slot['weekday'] as num?)?.toInt());
    if (_isAlwaysAvailableSlot(slot)) {
      result.add(
        dayLabel.isNotEmpty
            ? '$dayLabel • Toujours disponible'
            : 'Toujours disponible',
      );
      continue;
    }

    final from = _formatAvailabilityTime(
      hour: (slot['fromHour'] as num?)?.toInt(),
      minute: (slot['fromMinute'] as num?)?.toInt(),
      period: slot['fromPeriod']?.toString(),
    );
    final to = _formatAvailabilityTime(
      hour: (slot['toHour'] as num?)?.toInt(),
      minute: (slot['toMinute'] as num?)?.toInt(),
      period: slot['toPeriod']?.toString(),
    );
    if (from != null && to != null) {
      result.add(
        dayLabel.isNotEmpty ? '$dayLabel • $from - $to' : '$from - $to',
      );
      continue;
    }

    final existingLabel = (slot['label']?.toString() ?? '').trim();
    if (existingLabel.isNotEmpty) {
      result.add(
        dayLabel.isNotEmpty && !existingLabel.toLowerCase().startsWith(dayLabel)
            ? '$dayLabel • $existingLabel'
            : existingLabel,
      );
    }
  }
  return result;
}

String _weekdayLabel(int? weekday) {
  const weekdays = ['', 'lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
  if (weekday == null || weekday < 1 || weekday > 7) return '';
  return weekdays[weekday];
}

bool _isAlwaysAvailableSlot(Map slot) {
  if (slot['allDay'] == true) return true;
  final label = (slot['label']?.toString() ?? '').toLowerCase();
  return label.contains('toujours disponible') ||
      label.contains('toute la journee') ||
      label.contains('toute la journ?e');
}

String? _formatAvailabilityTime({
  required int? hour,
  required int? minute,
  required String? period,
}) {
  if (hour == null) return null;
  final normalizedMinute = (minute ?? 0).clamp(0, 59);
  final normalizedPeriod = (period ?? '').trim().toUpperCase();
  if (normalizedPeriod == 'AM' || normalizedPeriod == 'PM') {
    return '$hour:${normalizedMinute.toString().padLeft(2, '0')}${normalizedPeriod.toLowerCase()}';
  }

  if (hour < 0 || hour > 23) return null;
  final suffix = hour >= 12 ? 'pm' : 'am';
  final normalizedHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$normalizedHour:${normalizedMinute.toString().padLeft(2, '0')}$suffix';
}

// -- Geocoding -----------------------------------------------------------------

class _LatLng {
  const _LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

Future<String> _readMapsKey() async {
  try {
    final raw = await rootBundle.loadString('.env');
    for (final sourceLine in raw.split('\n')) {
      final line = sourceLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separatorIndex = line.contains('=')
          ? line.indexOf('=')
          : line.contains(':')
              ? line.indexOf(':')
              : -1;
      if (separatorIndex <= 0) continue;
      final key = line.substring(0, separatorIndex).trim();
      if (key != 'GOOGLE_MAPS_API_KEY') continue;
      final value = line.substring(separatorIndex + 1).trim();
      if (value.isNotEmpty) return value;
    }
  } catch (_) {}
  return _kFallbackMapsKey;
}

Future<_LatLng?> _geocodeAddress(String address,
    {required String apiKey}) async {
  final normalizedAddress = address.trim();
  if (normalizedAddress.isEmpty) return null;
  if (_geocodeCache.containsKey(normalizedAddress)) {
    return _geocodeCache[normalizedAddress];
  }

  try {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': normalizedAddress,
      'key': apiKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      _geocodeCache[normalizedAddress] = null;
      return null;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') {
      _geocodeCache[normalizedAddress] = null;
      return null;
    }
    final loc = (body['results'] as List).first['geometry']['location'];
    final coords =
        _LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
    _geocodeCache[normalizedAddress] = coords;
    return coords;
  } catch (_) {
    _geocodeCache[normalizedAddress] = null;
    return null;
  }
}

Future<String?> _reverseGeocode({
  required double lat,
  required double lng,
  required String apiKey,
}) async {
  try {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$lat,$lng',
      'key': apiKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') return null;
    final results = body['results'] as List?;
    if (results == null || results.isEmpty) return null;
    return (results.first['formatted_address'] as String?)?.trim();
  } catch (_) {
    return null;
  }
}

double _haversineKm(_LatLng a, _LatLng b) {
  const r = 6371.0;
  final dLat = (b.lat - a.lat) * pi / 180;
  final dLng = (b.lng - a.lng) * pi / 180;
  final s = sin(dLat / 2) * sin(dLat / 2) +
      cos(a.lat * pi / 180) *
          cos(b.lat * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return 2 * r * asin(sqrt(s));
}

String _resolveWorkerRole({
  required String role,
  required String jobTitle,
  required String department,
  required String maintenanceType,
}) {
  if (role.isNotEmpty) return role;
  if (jobTitle.isNotEmpty) return jobTitle;
  if (maintenanceType.isNotEmpty) return maintenanceType;
  if (department.isNotEmpty) return department;
  return 'Intervenant';
}

String? _resolveWorkerSpecialty({
  required String specialty,
  required String speciality,
  required String specialtyFromList,
  required String maintenanceType,
}) {
  if (specialty.isNotEmpty) return specialty;
  if (speciality.isNotEmpty) return speciality;
  if (specialtyFromList.isNotEmpty) return specialtyFromList;
  if (maintenanceType.isNotEmpty) return maintenanceType;
  return null;
}

String _normalizeWorkerFilterValue(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _matchesNormalizedValue(String? left, String? right) {
  final normalizedLeft = _normalizeWorkerFilterValue(left);
  final normalizedRight = _normalizeWorkerFilterValue(right);
  return normalizedLeft.isNotEmpty &&
      normalizedRight.isNotEmpty &&
      normalizedLeft == normalizedRight;
}

bool _matchesWorkerDepartment(_WorkerItem worker, String departmentFilter) {
  if (_matchesNormalizedValue(worker.department, departmentFilter)) {
    return true;
  }
  return _matchesNormalizedValue(worker.specialty, departmentFilter);
}

String _resolveWorkerDepartment({
  required String department,
  required String role,
}) {
  if (department.isNotEmpty) return department;
  if (role.contains('Maintenance')) return 'Maintenance générale';
  if (role.contains('Houseman')) return 'Houseman';
  if (role.contains('Valet') || role.contains('Femme de chambre')) {
    return 'Ménage';
  }
  if (role.contains('Reception') || role.contains('Concierge')) {
    return 'Concierge';
  }
  if (role.contains('Superviseur')) return "Main-d'œuvre qualifiée";
  if (role.contains('Staff')) return "Main-d'œuvre qualifiée";
  return 'Préposé aux chambres';
}

bool _isQualifiedLaborDepartment(String? department) {
  final normalized = (department ?? '')
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('maindoeuvrequalifiee') ||
      normalized.contains('mainoeuvrequalifiee');
}

String _resolveWorkerDisplayHeadline({
  required String? department,
  required String? specialty,
  required String fallbackRole,
}) {
  final trimmedSpecialty = (specialty ?? '').trim();
  if (_isQualifiedLaborDepartment(department) && trimmedSpecialty.isNotEmpty) {
    return trimmedSpecialty;
  }
  final trimmedDepartment = (department ?? '').trim();
  if (trimmedDepartment.isNotEmpty) return trimmedDepartment;
  return fallbackRole;
}

String _workerInitials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'I';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

// -- Data models (unchanged) ----------------------------------------------------

class _WorkersPageData {
  const _WorkersPageData({
    required this.property,
    required this.workers,
    required this.allWorkers,
    required this.departments,
    required this.roleOptions,
    required this.specialtyOptions,
    required this.propertyAddressDefined,
    required this.distanceFilteringSupported,
    required this.locationPending,
  });

  final _PropertyInfo? property;
  final List<_WorkerItem> workers;
  final List<_WorkerItem> allWorkers;
  final List<String> departments;
  final List<String> roleOptions;
  final List<String> specialtyOptions;
  final bool propertyAddressDefined;
  final bool distanceFilteringSupported;
  final bool locationPending;
}

class _PropertyInfo {
  const _PropertyInfo({
    required this.id,
    required this.name,
    required this.address,
  });

  final String id;
  final String? name;
  final String? address;
}

class _WorkerItem {
  const _WorkerItem({
    required this.id,
    required this.fullName,
    required this.role,
    required this.department,
    required this.specialty,
    required this.displayHeadline,
    required this.profileImageUrl,
    required this.photoBase64,
    required this.isVerified,
    required this.isAvailableNow,
    required this.availabilityLabel,
    required this.availabilitySlots,
    required this.experienceYears,
    required this.rating,
    required this.address,
    this.distanceKm,
  });

  final String id;
  final String fullName;
  final String role;
  final String? department;
  final String? specialty;
  final String displayHeadline;
  final String? profileImageUrl;
  final String? photoBase64;
  final bool isVerified;
  final bool isAvailableNow;
  final String? availabilityLabel;
  final List<String> availabilitySlots;
  final double? experienceYears;
  final double? rating;
  final String? address;
  final double? distanceKm;
}

Uint8List? _decodeWorkerPhotoBase64(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }
  try {
    final normalized = rawValue.contains(',')
        ? rawValue.split(',').last.trim()
        : rawValue.trim();
    return base64Decode(normalized);
  } catch (_) {
    return null;
  }
}

// -------------------------------------------------------------------------------
// UI Widgets — new dark-gold design
// -------------------------------------------------------------------------------

// -- _HeroRoundButton ----------------------------------------------------------
class _HeroRoundButton extends StatelessWidget {
  const _HeroRoundButton({
    required this.icon,
    required this.onTap,
  });

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
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// -- _DepartmentChip -----------------------------------------------------------
class _DepartmentChip extends StatelessWidget {
  const _DepartmentChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        decoration: BoxDecoration(
          color: isActive ? kAuthGold : const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? kAuthGold : Colors.white.withValues(alpha: 0.15),
            width: isActive ? 0 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: kAuthGold.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive
                  ? Colors.black
                  : Colors.white.withValues(alpha: 0.70),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive
                    ? Colors.black
                    : Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- _CompactWorkerAvatar ------------------------------------------------------
class _CompactWorkerAvatar extends StatelessWidget {
  const _CompactWorkerAvatar({required this.worker});

  final _WorkerItem worker;

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeWorkerPhotoBase64(worker.photoBase64);
    final imageUrl = worker.profileImageUrl;
    final initials = _workerInitials(worker.fullName);

    Widget imageChild;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      imageChild = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          if (imageBytes != null) {
            return Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _AvatarInitials(initials: initials),
            );
          }
          return _AvatarInitials(initials: initials);
        },
      );
    } else if (imageBytes != null) {
      imageChild = Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _AvatarInitials(initials: initials),
      );
    } else {
      imageChild = _AvatarInitials(initials: initials);
    }

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1E1E),
              border: Border.all(
                color: kAuthGold.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: ClipOval(child: imageChild),
          ),
          if (worker.isAvailableNow)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: kGreenDot,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF141414),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  LucideIcons.check,
                  color: Colors.white,
                  size: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.initials});

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
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// -- _MetaChip -----------------------------------------------------------------
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.45), size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// -- _MetaSeparator ------------------------------------------------------------
class _MetaSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Text(
        '|',
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.20),
          fontSize: 12,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}

// -- _AvailabilitySlotPill -----------------------------------------------------
class _AvailabilitySlotPill extends StatelessWidget {
  const _AvailabilitySlotPill({
    required this.label,
    this.isAlwaysAvailable = false,
  });

  final String label;
  final bool isAlwaysAvailable;

  @override
  Widget build(BuildContext context) {
    final color = isAlwaysAvailable ? kGreenDot : kAuthGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAlwaysAvailable) ...[
            const SizedBox(
              width: 6,
              height: 6,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: kGreenDot, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// -- _CompactWorkerCard --------------------------------------------------------
class _CompactWorkerCard extends StatelessWidget {
  const _CompactWorkerCard({
    required this.worker,
    required this.isExpanded,
    required this.onToggle,
    required this.onProfileTap,
    required this.onSelectTap,
  });

  final _WorkerItem worker;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onProfileTap;
  final VoidCallback onSelectTap;

  @override
  Widget build(BuildContext context) {
    // Build availability pills: prefer parsed slots, fall back to label/status
    final pills = <String>[];
    if (worker.availabilitySlots.isNotEmpty) {
      pills.addAll(worker.availabilitySlots);
    } else if (worker.availabilityLabel != null) {
      pills.add(worker.availabilityLabel!);
    }
    if (worker.isAvailableNow && pills.isEmpty) {
      pills.add('Toujours disponible');
    }

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isExpanded
                ? kAuthGold.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.08),
            width: isExpanded ? 1.5 : 1,
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: kAuthGold.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // -- Header row ----------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CompactWorkerAvatar(worker: worker),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name + verified badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              worker.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (worker.isVerified) ...[
                            const SizedBox(width: 5),
                            Icon(
                              LucideIcons.badgeCheck,
                              color: kAuthGold.withValues(alpha: 0.85),
                              size: 15,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Role in gold
                      Text(
                        worker.displayHeadline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: kAuthGold,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Meta row: experience | distance
                      _WorkerMetaRow(worker: worker),
                      if (worker.address != null &&
                          worker.address!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          worker.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.40),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronRight,
                  color: kAuthGold.withValues(alpha: 0.80),
                  size: 20,
                ),
              ],
            ),

            // -- Expanded section -----------------------------------------
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Divider(
                color: kAuthGold.withValues(alpha: 0.15),
                height: 1,
                thickness: 1,
              ),
              const SizedBox(height: 12),
              if (pills.isNotEmpty) ...[
                Text(
                  'Disponibilités',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in pills)
                      _AvailabilitySlotPill(
                        label: label,
                        isAlwaysAvailable:
                            label.toLowerCase().contains('toujours disponible'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onProfileTap,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: kAuthGold.withValues(alpha: 0.60),
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.user,
                              size: 13,
                              color: kAuthGold.withValues(alpha: 0.80)),
                          const SizedBox(width: 7),
                          Text(
                            'Voir profil',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onSelectTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAuthGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              LucideIcons.check,
                              size: 11,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'StayUp',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -- _WorkerMetaRow -------------------------------------------------------------
class _WorkerMetaRow extends StatelessWidget {
  const _WorkerMetaRow({required this.worker});

  final _WorkerItem worker;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];

    if (worker.experienceYears != null) {
      segments.add(_MetaChip(
        icon: LucideIcons.briefcase,
        label: '${worker.experienceYears!.round()} ans',
      ));
    }
    if (worker.distanceKm != null) {
      if (segments.isNotEmpty) segments.add(_MetaSeparator());
      segments.add(_MetaChip(
        icon: LucideIcons.navigation,
        label: '${worker.distanceKm!.toStringAsFixed(1)} km',
      ));
    }
    if (worker.rating != null && worker.rating! > 0) {
      if (segments.isNotEmpty) segments.add(_MetaSeparator());
      segments.add(_MetaChip(
        icon: LucideIcons.star,
        label: worker.rating!.toStringAsFixed(1),
      ));
    }

    if (segments.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: segments,
    );
  }
}

// -- _NavItem ------------------------------------------------------------------
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
                    isActive ? kAuthGold : Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- _WorkersEmptyCard (dark) --------------------------------------------------
class _WorkerCardSkeleton extends StatefulWidget {
  const _WorkerCardSkeleton();

  @override
  State<_WorkerCardSkeleton> createState() => _WorkerCardSkeletonState();
}

class _WorkerCardSkeletonState extends State<_WorkerCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: kDarkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = 0.16 + (_controller.value * 0.18);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(
                  width: 66,
                  height: 66,
                  borderRadius: 33,
                  opacity: pulse + 0.08,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBlock(
                        width: 152,
                        height: 16,
                        opacity: pulse + 0.10,
                      ),
                      const SizedBox(height: 10),
                      _SkeletonBlock(
                        width: 126,
                        height: 13,
                        opacity: pulse + 0.06,
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          _SkeletonBlock(
                            width: 74,
                            height: 11,
                            opacity: pulse,
                          ),
                          const SizedBox(width: 10),
                          _SkeletonBlock(
                            width: 86,
                            height: 11,
                            opacity: pulse,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SkeletonBlock(
                        width: double.infinity,
                        height: 11,
                        opacity: pulse - 0.02,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SkeletonBlock(
                  width: 12,
                  height: 12,
                  borderRadius: 6,
                  opacity: pulse,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.opacity,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double opacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final clampedOpacity = opacity.clamp(0.06, 0.40);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: clampedOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _WorkersEmptyCard extends StatelessWidget {
  const _WorkersEmptyCard({required this.onModifyFilters});

  final VoidCallback onModifyFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.users, color: kAuthGold, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'Aucun intervenant trouvé',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ajustez vos filtres pour voir plus de résultats.',
              style: GoogleFonts.manrope(
                color: Colors.white.withValues(alpha: 0.90),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onModifyFilters,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kAuthGold.withValues(alpha: 0.70)),
                foregroundColor: kAuthGold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              ),
              child: Text(
                'Modifier les filtres',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- _WorkersErrorCard (dark) --------------------------------------------------
class _WorkersErrorCard extends StatelessWidget {
  const _WorkersErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(LucideIcons.wifiOff, color: kAuthGold, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'Erreur de chargement',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vérifiez votre connexion puis réessayez.',
              style: GoogleFonts.manrope(
                color: kWhite70,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAuthGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                elevation: 0,
              ),
              child: Text(
                'Réessayer',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------
// Filter sheet — completely unchanged
// -------------------------------------------------------------------------------

class _WorkersFilterSheet extends StatefulWidget {
  const _WorkersFilterSheet({
    required this.initialState,
    required this.departments,
    required this.roleOptions,
    required this.specialtyOptions,
    required this.propertyAddressDefined,
    required this.distanceFilteringSupported,
  });

  final WorkerFilterState initialState;
  final List<String> departments;
  final List<String> roleOptions;
  final List<String> specialtyOptions;
  final bool propertyAddressDefined;
  final bool distanceFilteringSupported;

  @override
  State<_WorkersFilterSheet> createState() => _WorkersFilterSheetState();
}

class _WorkersFilterSheetState extends State<_WorkersFilterSheet> {
  late WorkerFilterState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _state.availabilityDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kAuthGoldDark,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: kAuthText,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(
      () => _state = _state.copyWith(
        availableNow: false,
        availabilityDate: picked,
      ),
    );
  }

  Future<void> _selectSingleValue({
    required String title,
    required List<String> options,
    required String? currentValue,
    required ValueChanged<String?> onSelected,
  }) async {
    if (options.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelectionSheet(
        title: title,
        options: options,
        currentValue: currentValue,
      ),
    );
    if (!mounted) return;
    onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topInset = mediaQuery.padding.top;

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          height: mediaQuery.size.height * 0.86,
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                top: topInset + 8,
                child: Container(
                  decoration: const BoxDecoration(
                    color: kAuthPanel,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kAuthDivider,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            22,
                            18,
                            22,
                            mediaQuery.padding.bottom + 26,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _HeroRoundButton(
                                    icon: LucideIcons.arrowLeft,
                                    onTap: () => Navigator.pop(context),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Filtres de recherche',
                                      style: GoogleFonts.cormorantGaramond(
                                        color: kAuthGoldDark,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    LucideIcons.slidersHorizontal,
                                    color: kAuthGoldDark,
                                    size: 20,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _FilterFieldCard(
                                icon: LucideIcons.briefcase,
                                label: 'Departement',
                                value: _state.department ??
                                    'Selectionnez un departement',
                                onTap: () => _selectSingleValue(
                                  title: 'Departement',
                                  options: widget.departments,
                                  currentValue: _state.department,
                                  onSelected: (value) {
                                    setState(
                                      () => _state = _state.copyWith(
                                        department: value,
                                        clearRole: true,
                                        clearSpecialty: true,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              _FilterFieldCard(
                                icon: LucideIcons.user,
                                label: 'Role',
                                value: _state.role ?? 'Selectionnez un role',
                                enabled: widget.roleOptions.isNotEmpty,
                                onTap: widget.roleOptions.isEmpty
                                    ? null
                                    : () => _selectSingleValue(
                                          title: 'Role',
                                          options: widget.roleOptions,
                                          currentValue: _state.role,
                                          onSelected: (value) {
                                            setState(
                                              () => _state = _state.copyWith(
                                                role: value,
                                                clearSpecialty: true,
                                              ),
                                            );
                                          },
                                        ),
                              ),
                              const SizedBox(height: 12),
                              _FilterFieldCard(
                                icon: LucideIcons.wrench,
                                label: 'Specialite',
                                value: _state.specialty ??
                                    'Selectionnez une specialite',
                                enabled: widget.specialtyOptions.isNotEmpty,
                                onTap: widget.specialtyOptions.isEmpty
                                    ? null
                                    : () => _selectSingleValue(
                                          title: 'Specialite',
                                          options: widget.specialtyOptions,
                                          currentValue: _state.specialty,
                                          onSelected: (value) {
                                            setState(
                                              () => _state = _state.copyWith(
                                                specialty: value,
                                              ),
                                            );
                                          },
                                        ),
                              ),
                              const SizedBox(height: 12),
                              _SliderFieldCard(
                                icon: LucideIcons.barChart3,
                                label: 'Annees d experience',
                                valueLabel: '${_state.experience.round()}+ ans',
                                sliderValue: _state.experience,
                                min: 0,
                                max: 10,
                                leftLabel: '0 an',
                                centerLabel: '5+ ans',
                                rightLabel: '10+ ans',
                                onChanged: (value) {
                                  setState(
                                    () => _state =
                                        _state.copyWith(experience: value),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _SliderFieldCard(
                                icon: LucideIcons.mapPin,
                                label: 'Kilometrage maximum',
                                valueLabel:
                                    '${_state.maxDistanceKm.round()} km',
                                sliderValue: _state.maxDistanceKm,
                                min: 5,
                                max: 50,
                                leftLabel: '5 km',
                                centerLabel: '20 km',
                                rightLabel: '50 km',
                                enabled: widget.distanceFilteringSupported,
                                helperText: !widget.propertyAddressDefined
                                    ? 'Adresse non definie'
                                    : !widget.distanceFilteringSupported
                                        ? 'Distance indisponible pour les intervenants actuels'
                                        : null,
                                onChanged: widget.distanceFilteringSupported
                                    ? (value) {
                                        setState(
                                          () => _state = _state.copyWith(
                                            maxDistanceKm: value,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                              if (!widget.propertyAddressDefined) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'Definir l adresse',
                                      style: GoogleFonts.manrope(
                                        color: kAuthGoldDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                'Disponibilite',
                                style: GoogleFonts.manrope(
                                  color: kAuthText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _AvailabilityPill(
                                      icon: LucideIcons.calendar,
                                      label: 'Disponible maintenant',
                                      selected: _state.availableNow,
                                      onTap: () {
                                        setState(
                                          () => _state = _state.copyWith(
                                            availableNow: !_state.availableNow,
                                            clearAvailabilityDate: true,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _AvailabilityPill(
                                      icon: LucideIcons.calendarDays,
                                      label: _state.availabilityDate == null
                                          ? 'Choisir une date'
                                          : '${_state.availabilityDate!.day}/${_state.availabilityDate!.month}/${_state.availabilityDate!.year}',
                                      selected: _state.availabilityDate != null,
                                      onTap: _pickDate,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _SearchActionButton(
                                label: 'Rechercher',
                                onTap: () => Navigator.pop(context, _state),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    setState(
                                      () => _state = const WorkerFilterState(),
                                    );
                                  },
                                  child: Text(
                                    'Reinitialiser',
                                    style: GoogleFonts.manrope(
                                      color: kAuthGoldDark,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: kAuthDivider),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color:
                                            kAuthGold.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.users,
                                        color: kAuthGoldDark,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Besoin d aide pour choisir ?',
                                            style: GoogleFonts.manrope(
                                              color: kAuthText,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Nous sommes la pour vous conseiller.',
                                            style: GoogleFonts.manrope(
                                              color: kAuthMuted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      LucideIcons.chevronRight,
                                      color: kAuthText,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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

class _FilterFieldCard extends StatelessWidget {
  const _FilterFieldCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kAuthDivider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8EF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: enabled ? kAuthGoldDark : kAuthMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        color: kAuthText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: enabled ? kAuthMuted : kAuthDivider,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                color: enabled ? kAuthText : kAuthDivider,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderFieldCard extends StatelessWidget {
  const _SliderFieldCard({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.sliderValue,
    required this.min,
    required this.max,
    required this.leftLabel,
    required this.centerLabel,
    required this.rightLabel,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double sliderValue;
  final double min;
  final double max;
  final String leftLabel;
  final String centerLabel;
  final String rightLabel;
  final ValueChanged<double>? onChanged;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kAuthDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8EF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: enabled ? kAuthGoldDark : kAuthMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        color: kAuthText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      helperText ?? valueLabel,
                      style: GoogleFonts.manrope(
                        color: enabled ? kAuthMuted : kAuthGoldDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronDown,
                color: kAuthText,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: kAuthGoldDark,
              inactiveTrackColor: kAuthDivider,
              thumbColor: Colors.white,
              overlayColor: kAuthGold.withValues(alpha: 0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            ),
            child: Slider(
              value: sliderValue.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  leftLabel,
                  style: GoogleFonts.manrope(
                    color: kAuthMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  centerLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: kAuthMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rightLabel,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.manrope(
                    color: kAuthMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? kAuthGoldDark : kAuthDivider,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? kAuthGoldDark : kAuthText, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: kAuthText,
                    fontSize: 13,
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

class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({
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
          height: 60,
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
                margin: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: kAuthGold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.search,
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

class _SelectionSheet extends StatelessWidget {
  const _SelectionSheet({
    required this.title,
    required this.options,
    required this.currentValue,
  });

  final String title;
  final List<String> options;
  final String? currentValue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: kAuthPanel,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).padding.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kAuthDivider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.cormorantGaramond(
                  color: kAuthText,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _OptionTile(
                        label: 'Aucune selection',
                        selected: currentValue == null,
                        onTap: () => Navigator.pop(context, null),
                      );
                    }
                    final option = options[index - 1];
                    return _OptionTile(
                      label: option,
                      selected: option == currentValue,
                      onTap: () => Navigator.pop(context, option),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? kAuthGoldDark : kAuthDivider,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: selected ? kAuthGoldDark : kAuthText,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.check,
                  color: kAuthGoldDark,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
