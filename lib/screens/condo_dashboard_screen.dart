import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_os/providers/hotel_provider.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/screens/building_management_screen.dart';
import 'package:hotel_lux_os/screens/intervenants_screen.dart';
import 'package:hotel_lux_os/screens/manager_chat_thread_screen.dart';
import 'package:hotel_lux_os/screens/manager_messages_screen.dart';
import 'package:hotel_lux_os/screens/manager_notifications_screen.dart';
import 'package:hotel_lux_os/screens/manager_offers_screen.dart';
import 'package:hotel_lux_os/screens/manager_property_route_helper.dart';
import 'package:hotel_lux_os/services/app_session_service.dart';
import 'package:hotel_lux_os/services/manager_worker_contact_service.dart';
import 'package:hotel_lux_os/services/property_scope_service.dart';
import 'package:hotel_lux_os/services/vps_media_service.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:hotel_lux_os/widgets/unread_messages_nav_item.dart';
import 'package:provider/provider.dart';

const _kDashBg = Color(0xFF070707);
const _kDashPanel = Color(0xFF090909);
const _kDashCard = Color(0xFF141414);
const _kDashBorder = Color(0x33D6A85A);
const _kStoryBlue = Color(0xFF2F8CFF);
const _kFallbackMapsKey = '';

final Map<String, _LatLng?> _storyGeocodeCache = <String, _LatLng?>{};

class CondoDashboardScreen extends StatefulWidget {
  const CondoDashboardScreen({
    super.key,
    this.propertyType,
    this.accessRole,
  });

  final String? propertyType;
  final String? accessRole;

  @override
  State<CondoDashboardScreen> createState() => _CondoDashboardScreenState();
}

class _CondoDashboardScreenState extends State<CondoDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<_DashboardData> _future;
  _LatLng? _deviceCoords;

  String get _sessionUid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  bool get _isApartmentScopedAccess =>
      widget.accessRole == 'apartment_account' ||
      widget.accessRole == 'apartment_manager';

  bool get _showsBuildingManagement =>
      isBuildingPropertyType(widget.propertyType) ||
      (widget.accessRole?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    unawaited(_ensureInitialLocationContext());
  }

  Future<void> _ensureInitialLocationContext() async {
    final uid = _sessionUid;
    if (uid.isEmpty) return;
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snapshot = await userRef.get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final alreadyPrompted = data['managerHomepageLocationPromptedAt'] != null;

      var permission = await Geolocator.checkPermission();
      if (!alreadyPrompted && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        await userRef.set({
          'managerHomepageLocationPromptedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _future = _loadData();
        });
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() {
        _deviceCoords = _LatLng(position.latitude, position.longitude);
        _future = _loadData();
      });
    } catch (_) {}
  }

  Future<_DashboardData> _loadData() async {
    final uid = _sessionUid;
    if (uid.isEmpty) {
      throw StateError('user-not-found');
    }

    final now = Timestamp.now();
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(uid).get(),
      FirebaseFirestore.instance.collection('stories').get(),
      _readMapsKey(),
    ]);

    final userData =
        (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ??
            const <String, dynamic>{};
    final storyDocs = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;
    final mapsKey = results[2] as String;

    final accountType = PropertyScopeService.normalizeAccountType(userData);
    final assignedPropertyIds = PropertyScopeService.scopedPropertyIds(userData);

    List<DocumentSnapshot<Map<String, dynamic>>> condoDocs;
    if (accountType == 'apartment_account') {
      condoDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      if (assignedPropertyIds.isNotEmpty) {
        for (final propertyId in assignedPropertyIds) {
          final doc = await FirebaseFirestore.instance
              .collection('hotels')
              .doc(propertyId)
              .get();
          if (doc.exists) {
            condoDocs.add(doc);
          }
        }
      } else {
        final snapshot = await FirebaseFirestore.instance
            .collection('hotels')
            .where('accountUid', isEqualTo: uid)
            .limit(1)
            .get();
        condoDocs = snapshot.docs;
      }
    } else if (accountType == 'manager' ||
        accountType == 'concierge' ||
        accountType == 'apartment_manager') {
      condoDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final propertyId in assignedPropertyIds) {
        final doc = await FirebaseFirestore.instance
            .collection('hotels')
            .doc(propertyId)
            .get();
        if (doc.exists) condoDocs.add(doc);
      }
    } else {
      final snapshot = await FirebaseFirestore.instance
          .collection('hotels')
          .where('ownerId', isEqualTo: uid)
          .limit(12)
          .get();
      condoDocs = snapshot.docs
          .where((doc) =>
              ((doc.data()['status'] as String?)?.trim().toLowerCase() ??
                  'active') !=
              'deleted')
          .toList();
    }

    final firstName = (userData['firstName'] as String?)?.trim() ?? '';
    final lastName = (userData['lastName'] as String?)?.trim() ?? '';
    final fullName =
        ([firstName, lastName]..removeWhere((e) => e.isEmpty)).join(' ').trim();
    final fallbackName =
        (userData['username'] as String?)?.trim().isNotEmpty == true
            ? (userData['username'] as String).trim()
            : 'Manager';

    final condoData = condoDocs.isNotEmpty
        ? (condoDocs.first.data() ?? const <String, dynamic>{})
        : const <String, dynamic>{};
    final condoName = (condoData['name'] as String?)?.trim().isNotEmpty == true
        ? (condoData['name'] as String).trim()
        : accountType == 'concierge'
            ? 'Appartements assignes'
            : widget.propertyType == 'building_manager' ||
                    widget.propertyType == 'rental_building'
                ? 'Votre immeuble'
            : 'Votre condo';
    final location =
        (condoData['location'] as String?)?.trim().isNotEmpty == true
            ? (condoData['location'] as String).trim()
            : 'Adresse a configurer';
    final scopeLabel =
        (accountType == 'apartment_account' || accountType == 'apartment_manager') &&
                condoName.isNotEmpty
            ? 'Appartement: $condoName'
            : null;

    final managerCoords = _deviceCoords ??
        (location.isNotEmpty && location != 'Adresse a configurer'
            ? await _geocodeAddress(location, apiKey: mapsKey)
            : null);

    final nowDate = now.toDate();
    final activeStoryDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final ownerIds = <String>{};
    final prefilteredDistances = <String, double?>{};
    final groupedStories = <String, List<_StoryEntry>>{};
    for (final doc in storyDocs) {
      final data = doc.data();
      if (!_isStoryStillActive(data, nowDate)) continue;
      final ownerId = _resolveStoryOwnerId(data);
      if (ownerId == null || ownerId.isEmpty) continue;
      final latitude =
          _readCoordinate(data, ['latitude', 'storyLatitude', 'lat']);
      final longitude =
          _readCoordinate(data, ['longitude', 'storyLongitude', 'lng', 'lon']);
      if (managerCoords != null && latitude != null && longitude != null) {
        final distanceKm =
            _haversineKm(managerCoords, _LatLng(latitude, longitude));
        if (distanceKm > 20) continue;
        prefilteredDistances[ownerId] = distanceKm;
      }
      activeStoryDocs.add(doc);
      ownerIds.add(ownerId);
    }

    final workerDocs = await Future.wait(
      ownerIds.map(
        (ownerId) => FirebaseFirestore.instance
            .collection('profiles')
            .doc(ownerId)
            .get(),
      ),
    );
    final workerMap = <String, _StoryWorker>{};
    for (final doc in workerDocs) {
      final data = doc.data();
      if (data == null || !doc.exists) continue;
      final worker = _StoryWorker(
        id: doc.id,
        name: _resolveWorkerName(data),
        specialty: _resolveWorkerSpecialty(data),
        photoBase64: _readPhotoBase64(data),
        photoUrl: VpsMediaService.resolveProfileImageUrl(data),
        phone: (data['phone'] as String?)?.trim(),
        address: _resolveWorkerAddress(data),
        stories: const [],
      );
      for (final key in _profileMatchKeys(doc.id, data)) {
        workerMap[key] = worker;
      }
    }

    for (final doc in activeStoryDocs) {
      final ownerId = _resolveStoryOwnerId(doc.data());
      if (ownerId == null || ownerId.isEmpty) continue;
      final worker = workerMap[ownerId];
      if (worker == null) continue;
      final entry = _storyEntryFromDoc(doc, worker);
      if (entry == null) continue;
      groupedStories.putIfAbsent(ownerId, () => <_StoryEntry>[]).add(entry);
    }

    // Parallelize per-worker geocoding so GPS filtering is fast.
    final rawEntries = groupedStories.entries.toList();
    final resolvedWorkers = await Future.wait(
      rawEntries.map((entry) async {
        final worker = workerMap[entry.key];
        if (worker == null) return null;
        final sortedStories = [...entry.value]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final storyCoords = _resolveStoryCoords(sortedStories);
        double? distanceKm = prefilteredDistances[entry.key];
        if (managerCoords != null) {
          final comparisonCoords = storyCoords ??
              (distanceKm == null
                  ? await _resolveWorkerCoords(worker.address, apiKey: mapsKey)
                  : null);
          if (distanceKm == null && comparisonCoords != null) {
            distanceKm = _haversineKm(managerCoords, comparisonCoords);
          }
        }

        if (managerCoords != null && distanceKm != null && distanceKm > 20) {
          return null;
        }

        return worker.copyWith(
          stories: sortedStories,
          distanceKm: distanceKm,
        );
      }),
    );
    final storyWorkers = resolvedWorkers.whereType<_StoryWorker>().toList();

    storyWorkers.sort((a, b) {
      final aTime = a.stories.last.createdAt;
      final bTime = b.stories.last.createdAt;
      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) return byTime;
      return (a.distanceKm ?? double.infinity)
          .compareTo(b.distanceKm ?? double.infinity);
    });

    return _DashboardData(
      managerName: fullName.isNotEmpty ? fullName : fallbackName,
      propertyRole: accountType == 'concierge'
          ? 'Concierge'
          : accountType == 'manager'
              ? 'Gestionnaire immeuble'
              : accountType == 'apartment_manager'
                  ? 'Gestionnaire'
                  : accountType == 'apartment_account'
                      ? 'Compte appartement'
                  : widget.propertyType == 'villa_owner'
                      ? 'Proprietaire de villa'
                      : widget.propertyType == 'building_manager'
                          ? 'Proprietaire d immeuble'
                          : 'Proprietaire d appartement / condo',
      condoName: condoName,
      condoLocation: location,
      scopeLabel: scopeLabel,
      hasApartments: condoDocs.isNotEmpty,
      stories: storyWorkers,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildManagerProfileScreen(
          propertyType: widget.propertyType,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Provider.of<HotelProvider>(context, listen: false).logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _kDashBg,
      extendBody: true,
      drawer: _ManagerDashboardDrawer(
        propertyType: widget.propertyType,
        accessRole: widget.accessRole,
        onProfile: _openProfile,
        onMessages: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ManagerMessagesScreen()),
        ),
        onIntervenants: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
        ),
        onOffers: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ManagerOffersScreen()),
        ),
        onPropertyManagement: () {
          if (_showsBuildingManagement) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BuildingManagementScreen(),
              ),
            );
            return;
          }
          _openProfile();
        },
        onSettings: _openProfile,
        onLogout: _logout,
      ),
      bottomNavigationBar: _DashboardNav(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) return;
          if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ManagerOffersScreen()),
            );
          } else if (index == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ManagerMessagesScreen()),
            );
          } else if (index == 4) {
            _openProfile();
          }
        },
      ),
      body: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertTriangle, color: kAuthGold),
                    const SizedBox(height: 12),
                    Text(
                      'Impossible de charger le tableau de bord pour le moment.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return _DashboardSkeleton(propertyType: widget.propertyType);
          }

          final data = snapshot.data!;
          final topInset = MediaQuery.paddingOf(context).top;

          return RefreshIndicator(
            color: kAuthGold,
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: 240,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/conduheroimg.webp',
                        fit: BoxFit.cover,
                        alignment: Alignment.topRight,
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x55000000),
                              Color(0xAA000000),
                              Color(0xFF070707),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _HeroCircleButton(
                                  icon: LucideIcons.menu,
                                  onTap: () =>
                                      _scaffoldKey.currentState?.openDrawer(),
                                ),
                                const Spacer(),
                                _HeroCircleButton(
                                  icon: LucideIcons.bell,
                                  badge: true,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ManagerNotificationsScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _HeroCircleButton(
                                  icon: LucideIcons.settings,
                                  onTap: _openProfile,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Bonjour',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.74),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              data.managerName,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data.propertyRole,
                              style: GoogleFonts.inter(
                                color: kAuthGold,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.mapPin,
                                  size: 14,
                                  color: kAuthGold.withValues(alpha: 0.84),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    data.scopeLabel ?? data.condoName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height - 220,
                    ),
                    decoration: const BoxDecoration(
                      color: _kDashPanel,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        0, 14, 0,
                        data.stories.isEmpty ? 16 : 100,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_showsBuildingManagement &&
                              !_isApartmentScopedAccess) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _BuildingManagerActionGrid(
                                accessRole: widget.accessRole,
                                hasApartments: data.hasApartments,
                                onAddProperty: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const BuildingManagementScreen(
                                        autoOpenApartmentForm: true,
                                      ),
                                    ),
                                  );
                                },
                                onAddManager: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const BuildingManagementScreen(
                                        pendingMemberAccountType:
                                            'apartment_manager',
                                      ),
                                    ),
                                  );
                                },
                                onAddConcierge: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const BuildingManagementScreen(
                                        pendingMemberAccountType: 'concierge',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Stories des intervenants proches',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const IntervenantsScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Voir tout',
                                    style: GoogleFonts.inter(
                                      color: kAuthGold,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _WorkerStoriesSection(stories: data.stories),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _QuickActionCard(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const IntervenantsScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_showsBuildingManagement) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _BuildingManagerCard(
                                accessRole: widget.accessRole,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const BuildingManagementScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.managerName,
    required this.propertyRole,
    required this.condoName,
    required this.condoLocation,
    required this.scopeLabel,
    required this.hasApartments,
    required this.stories,
  });

  final String managerName;
  final String propertyRole;
  final String condoName;
  final String condoLocation;
  final String? scopeLabel;
  final bool hasApartments;
  final List<_StoryWorker> stories;
}

class _StoryWorker {
  const _StoryWorker({
    required this.id,
    required this.name,
    required this.specialty,
    required this.photoBase64,
    required this.photoUrl,
    required this.phone,
    required this.address,
    required this.stories,
    this.distanceKm,
  });

  final String id;
  final String name;
  final String specialty;
  final String? photoBase64;
  final String? photoUrl;
  final String? phone;
  final String? address;
  final List<_StoryEntry> stories;
  final double? distanceKm;

  _StoryWorker copyWith({
    List<_StoryEntry>? stories,
    double? distanceKm,
  }) {
    return _StoryWorker(
      id: id,
      name: name,
      specialty: specialty,
      photoBase64: photoBase64,
      photoUrl: photoUrl,
      phone: phone,
      address: address,
      stories: stories ?? this.stories,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

class _StoryEntry {
  const _StoryEntry({
    required this.id,
    required this.workerId,
    required this.mediaUrl,
    required this.kind,
    required this.mimeType,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.fileId,
    this.durationMs,
    this.caption,
  });

  final String id;
  final String workerId;
  final String mediaUrl;
  final String kind;
  final String mimeType;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final String? fileId;
  final int? durationMs;
  final String? caption;

  bool get isVideo =>
      kind == 'story-video' || mimeType.toLowerCase().startsWith('video/');
}

class _WorkerStoriesSection extends StatelessWidget {
  const _WorkerStoriesSection({
    required this.stories,
  });

  final List<_StoryWorker> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _WorkerStoriesEmpty(),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = math.min(250.0, screenWidth * 0.32);
    final cardHeight = cardWidth * 1.9;

    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: stories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final worker = stories[index];
          return _StoryCard(
            worker: worker,
            width: cardWidth,
            height: cardHeight,
          );
        },
      ),
    );
  }
}

class _StoryCard extends StatefulWidget {
  const _StoryCard({
    required this.worker,
    required this.width,
    required this.height,
  });

  final _StoryWorker worker;
  final double width;
  final double height;

  @override
  State<_StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<_StoryCard> {
  VideoPlayerController? _videoController;

  _StoryEntry get _coverStory => widget.worker.stories.last;

  @override
  void initState() {
    super.initState();
    _preparePreview();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final story in widget.worker.stories) {
        if (!story.isVideo) {
          precacheImage(NetworkImage(story.mediaUrl), context);
        }
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _preparePreview() async {
    final story = _coverStory;
    if (!story.isVideo) return;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(story.mediaUrl),
    );
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = widget.worker;
    final photoBytes = _decodePhoto(worker.photoBase64);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _StoryViewerScreen(worker: worker),
          ),
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StoryCardMedia(
              story: _coverStory,
              controller: _videoController,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.12),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.76),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            if (_coverStory.isVideo)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.volume2,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kAuthGold, _kStoryBlue],
                      ),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kDashBg,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: _buildWorkerPhoto(
                          photoUrl: worker.photoUrl,
                          photoBytes: photoBytes,
                          fallbackLabel: worker.name,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          worker.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          worker.specialty,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: kAuthGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
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
    );
  }
}

class _StoryCardMedia extends StatelessWidget {
  const _StoryCardMedia({
    required this.story,
    required this.controller,
  });

  final _StoryEntry story;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    if (story.isVideo) {
      if (controller != null && controller!.value.isInitialized) {
        final size = controller!.value.size;
        if (size.width > 0 && size.height > 0) {
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller!),
            ),
          );
        }
        // Initialized but 0×0 (codec didn't report dimensions yet)
        return VideoPlayer(controller!);
      }
      // Video not yet ready — show a dark placeholder
      return Container(
        color: const Color(0xFF0A0A0A),
        alignment: Alignment.center,
        child:
            const Icon(LucideIcons.playCircle, color: Colors.white30, size: 28),
      );
    }

    return Image.network(
      story.mediaUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFF0A0A0A),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            color: Colors.white24,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF111111),
        alignment: Alignment.center,
        child: const Icon(
          LucideIcons.imageOff,
          color: Colors.white70,
          size: 34,
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatefulWidget {
  const _DashboardSkeleton({this.propertyType});
  final String? propertyType;

  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<_DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _shimmer(
      {double width = double.infinity,
      double height = 16,
      double radius = 10}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Colors.white.withValues(alpha: 0.06 + _pulse.value * 0.08),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: _kDashBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.propertyType == 'villa_owner'
                      ? 'assets/conduheroimg.webp'
                      : 'assets/conduheroimg.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.topRight,
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Color(0xAA000000),
                        Color(0xFF070707),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      _shimmer(width: 90, height: 13),
                      const SizedBox(height: 10),
                      _shimmer(width: 200, height: 26, radius: 12),
                      const SizedBox(height: 8),
                      _shimmer(width: 140, height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -20),
            child: Container(
              decoration: const BoxDecoration(
                color: _kDashPanel,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmer(width: 220, height: 16),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          _shimmer(width: 130, height: 90, radius: 22),
                          if (i < 2) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _shimmer(height: 100, radius: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerStoriesEmpty extends StatelessWidget {
  const _WorkerStoriesEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kDashBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Icon(
              LucideIcons.playCircle,
              color: kAuthGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Aucune story active des intervenants proches pour le moment.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingManagerCard extends StatelessWidget {
  const _BuildingManagerCard({
    required this.accessRole,
    required this.onTap,
  });

  final String? accessRole;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = accessRole == 'apartment_account'
        ? 'Gestion de votre appartement'
        : accessRole == 'apartment_manager'
            ? 'Gestionnaire de votre appartement'
            : accessRole == 'concierge'
        ? 'Vos appartements et votre equipe'
        : accessRole == 'manager'
            ? 'Gestion immeuble et concierges'
            : 'Pilotage complet de l immeuble';
    final subtitle = accessRole == 'apartment_account'
        ? 'Retrouvez votre appartement, ses gestionnaires et ses concierges lies.'
        : accessRole == 'apartment_manager'
            ? 'Retrouvez l appartement auquel vous etes rattache et les comptes lies.'
            : accessRole == 'concierge'
        ? 'Retrouvez les appartements assignes et les membres de votre equipe.'
        : accessRole == 'manager'
            ? 'Ajoutez des concierges, distribuez les appartements et suivez les acces.'
            : 'Ajoutez plusieurs appartements, des gestionnaires et des concierges depuis un seul espace.';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kDashBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.building2,
                color: kAuthGold,
                size: 24,
              ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              color: kAuthGold,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildingManagerActionGrid extends StatelessWidget {
  const _BuildingManagerActionGrid({
    required this.accessRole,
    required this.hasApartments,
    this.onAddProperty,
    this.onAddManager,
    this.onAddConcierge,
  });

  final String? accessRole;
  final bool hasApartments;
  final VoidCallback? onAddProperty;
  final VoidCallback? onAddManager;
  final VoidCallback? onAddConcierge;

  @override
  Widget build(BuildContext context) {
    final isOwner = accessRole == null || accessRole!.trim().isEmpty;
    final isManager = accessRole == 'manager';
    final items = <({IconData icon, String label, VoidCallback? onTap})>[
      if (isOwner)
        (
          icon: LucideIcons.plus,
          label: hasApartments
              ? 'Ajouter un autre appartement'
              : 'Ajouter un appartement',
          onTap: onAddProperty,
        ),
      if (isOwner)
        (
          icon: LucideIcons.userPlus,
          label: 'Ajouter gestionnaire',
          onTap: onAddManager,
        ),
      if (isOwner || isManager)
        (
          icon: LucideIcons.key,
          label: 'Ajouter concierge',
          onTap: onAddConcierge,
        ),
    ].where((item) => item.onTap != null).toList();

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int index = 0; index < items.length; index++) ...[
            _BuildingActionChip(item: items[index]),
            if (index < items.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _BuildingActionChip extends StatelessWidget {
  const _BuildingActionChip({
    required this.item,
  });

  final ({IconData icon, String label, VoidCallback? onTap}) item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 176),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kDashBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: kAuthGold, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerDashboardDrawer extends StatelessWidget {
  const _ManagerDashboardDrawer({
    required this.propertyType,
    required this.accessRole,
    required this.onProfile,
    required this.onMessages,
    required this.onIntervenants,
    required this.onOffers,
    required this.onPropertyManagement,
    required this.onSettings,
    required this.onLogout,
  });

  final String? propertyType;
  final String? accessRole;
  final VoidCallback onProfile;
  final VoidCallback onMessages;
  final VoidCallback onIntervenants;
  final VoidCallback onOffers;
  final VoidCallback onPropertyManagement;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final isBuilding = isBuildingPropertyType(propertyType) ||
        (accessRole?.trim().isNotEmpty ?? false);
    final propertyLabel = isBuilding ? 'Gestion immeuble' : 'Gestion condo';

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: kAuthGold, size: 20),
        title: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    return Drawer(
      backgroundColor: const Color(0xFF0D0D0D),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Text(
                'StayFix',
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(color: _kDashBorder, height: 1),
            item(
              icon: LucideIcons.user,
              label: 'Profile',
              onTap: onProfile,
            ),
            item(
              icon: LucideIcons.messageCircle,
              label: 'Messages',
              onTap: onMessages,
            ),
            item(
              icon: LucideIcons.users,
              label: 'Intervenants',
              onTap: onIntervenants,
            ),
            item(
              icon: LucideIcons.clipboardList,
              label: 'Offres',
              onTap: onOffers,
            ),
            item(
              icon: LucideIcons.building2,
              label: propertyLabel,
              onTap: onPropertyManagement,
            ),
            item(
              icon: LucideIcons.settings,
              label: 'Parametres',
              onTap: onSettings,
            ),
            const Spacer(),
            const Divider(color: _kDashBorder, height: 1),
            item(
              icon: LucideIcons.logOut,
              label: 'Deconnexion',
              onTap: onLogout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _StoryViewerScreen extends StatefulWidget {
  const _StoryViewerScreen({
    required this.worker,
  });

  final _StoryWorker worker;

  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  int _storyLoadVersion = 0;
  bool _initializingImage = false;
  bool _initializingVideo = false;

  _StoryEntry get _currentStory => widget.worker.stories[_currentIndex];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _goNext();
        }
      });
    _startCurrentStory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final story in widget.worker.stories) {
        if (!story.isVideo) {
          precacheImage(NetworkImage(story.mediaUrl), context);
        }
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _startCurrentStory() async {
    final loadVersion = ++_storyLoadVersion;
    _progressController.stop();
    _progressController.value = 0;
    final previousController = _videoController;
    if (previousController != null) {
      previousController.removeListener(_handleVideoTick);
      await previousController.dispose();
    }
    _videoController = null;

    final story = _currentStory;
    if (!story.isVideo) {
      if (mounted) {
        setState(() => _initializingImage = true);
      }
      final imageLoaded = await _precacheStoryImage(story.mediaUrl);
      if (!mounted || loadVersion != _storyLoadVersion) return;
      setState(() => _initializingImage = false);
      final duration = Duration(milliseconds: story.durationMs ?? 5000);
      _progressController.duration =
          imageLoaded ? duration : const Duration(seconds: 6);
      unawaited(_progressController.forward(from: 0));
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _initializingImage = false;
      _initializingVideo = true;
    });
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
    try {
      await controller.initialize();
      if (!mounted || loadVersion != _storyLoadVersion) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(1);
      await controller.play();
      controller.addListener(_handleVideoTick);
      _videoController = controller;
      final sourceDuration = controller.value.duration.inMilliseconds > 0
          ? controller.value.duration
          : Duration(milliseconds: story.durationMs ?? 8000);
      _progressController.duration = sourceDuration;
      unawaited(_progressController.forward(from: 0));
    } catch (_) {
      await controller.dispose();
      if (!mounted || loadVersion != _storyLoadVersion) return;
      _progressController.duration = const Duration(seconds: 6);
      unawaited(_progressController.forward(from: 0));
    } finally {
      if (mounted && loadVersion == _storyLoadVersion) {
        setState(() => _initializingVideo = false);
      }
    }
  }

  Future<bool> _precacheStoryImage(String mediaUrl) async {
    try {
      await precacheImage(NetworkImage(mediaUrl), context);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleVideoTick() {
    final controller = _videoController;
    if (controller == null || !_progressController.isAnimating) return;
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration.inMilliseconds > 0) {
      final value =
          (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
      if ((value - _progressController.value).abs() > 0.01) {
        _progressController.value = value;
      }
    }
    if (controller.value.isInitialized &&
        !controller.value.isPlaying &&
        position >= duration &&
        duration > Duration.zero) {
      _goNext();
    }
  }

  Future<void> _goNext() async {
    if (_currentIndex >= widget.worker.stories.length - 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _currentIndex++);
    await _startCurrentStory();
  }

  Future<void> _goPrevious() async {
    if (_currentIndex == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _currentIndex--);
    await _startCurrentStory();
  }

  Future<void> _openConversation() async {
    try {
      final handle = await ManagerWorkerContactService.openConversation(
        workerId: widget.worker.id,
        workerName: widget.worker.name,
        workerRole: widget.worker.specialty,
        workerDepartment: widget.worker.specialty,
        workerPhotoBase64: widget.worker.photoBase64,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
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
      _showSnack('Cet intervenant est actuellement bloque.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d ouvrir cette conversation pour le moment.');
    }
  }

  Future<void> _callWorker() async {
    final raw = widget.worker.phone?.trim() ?? '';
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      _showSnack('Aucun numero disponible pour cet intervenant.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    _showSnack('Impossible d ouvrir le composeur telephonique.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoBytes = _decodePhoto(widget.worker.photoBase64);
    final story = _currentStory;
    final canCall = _hasCallablePhone(widget.worker.phone);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0).abs() > 450) {
            Navigator.of(context).pop();
          }
        },
        onTapUp: (details) {
          final width = MediaQuery.sizeOf(context).width;
          if (details.localPosition.dx < width * 0.35) {
            _goPrevious();
          } else {
            _goNext();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
                child: _StoryMedia(story: story, controller: _videoController)),
            if (_initializingImage || _initializingVideo)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) {
                        return Row(
                          children: List.generate(
                            widget.worker.stories.length,
                            (index) {
                              final progress = index < _currentIndex
                                  ? 1.0
                                  : index == _currentIndex
                                      ? _progressController.value
                                      : 0.0;
                              return Expanded(
                                child: Container(
                                  height: 4,
                                  margin: EdgeInsets.only(
                                    right: index ==
                                            widget.worker.stories.length - 1
                                        ? 0
                                        : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 42,
                          height: 42,
                          child: ClipOval(
                            child: _buildWorkerPhoto(
                              photoUrl: widget.worker.photoUrl,
                              photoBytes: photoBytes,
                              fallbackLabel: widget.worker.name,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.worker.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                widget.worker.specialty,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if ((story.caption ?? '').trim().isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            story.caption!.trim(),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _StoryActionButton(
                            icon: LucideIcons.messageCircle,
                            label: 'Contacter',
                            onTap: _openConversation,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StoryActionButton(
                            icon: LucideIcons.phoneCall,
                            label: 'Appeler',
                            enabled: canCall,
                            onTap: canCall ? _callWorker : null,
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
    );
  }
}

class _StoryMedia extends StatelessWidget {
  const _StoryMedia({
    required this.story,
    required this.controller,
  });

  final _StoryEntry story;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    if (story.isVideo) {
      if (controller != null && controller!.value.isInitialized) {
        final size = controller!.value.size;
        if (size.width > 0 && size.height > 0) {
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller!),
            ),
          );
        }
        // Initialized but no reported dimensions — fill the screen directly
        return VideoPlayer(controller!);
      }
      // Not yet initialized — black background while _initializingVideo shows spinner
      return const ColoredBox(color: Colors.black);
    }

    return Image.network(
      story.mediaUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF111111),
        alignment: Alignment.center,
        child: const Icon(
          LucideIcons.imageOff,
          color: Colors.white70,
          size: 34,
        ),
      ),
    );
  }
}

class _StoryActionButton extends StatelessWidget {
  const _StoryActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled && onTap != null ? () => onTap!() : null,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: enabled ? Colors.white : Colors.white38, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kDashCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kDashBorder),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kAuthGold.withValues(alpha: 0.72)),
              ),
              child: const Icon(
                LucideIcons.users,
                color: kAuthGold,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTION RAPIDE',
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Trouver un intervenant',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 25 / 1.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selectionnez le bon professionnel pour votre intervention.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: kAuthGold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.arrowRight,
                color: Colors.black,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCircleButton extends StatelessWidget {
  const _HeroCircleButton({
    required this.icon,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
        if (badge)
          const Positioned(
            top: 5,
            right: 6,
            child: UnreadMessagesDot(
              size: 9,
              color: Color(0xFFFF6B35),
              borderColor: _kDashBg,
            ),
          ),
      ],
    );
  }
}

class _DashboardNav extends StatelessWidget {
  const _DashboardNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const items = [
      _NavItem(icon: LucideIcons.home, label: 'Accueil'),
      _NavItem(icon: LucideIcons.users, label: 'Agents'),
      _NavItem(icon: LucideIcons.clipboardList, label: 'Offres'),
      _NavItem(icon: LucideIcons.messageCircle, label: 'Messages'),
      _NavItem(icon: LucideIcons.user, label: 'Profil'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? 6 : 12),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xEE101010),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final active = currentIndex == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.label == 'Messages')
                        UnreadMessagesNavItem(
                          isActive: active,
                          onTap: () => onTap(index),
                          activeColor: kAuthGold,
                          inactiveColor: Colors.white.withValues(alpha: 0.52),
                          dotColor: const Color(0xFFFF3B30),
                          activeSize: 20,
                          inactiveSize: 20,
                          padding: EdgeInsets.zero,
                          fontSize: 11,
                          activeFontWeight: FontWeight.w700,
                          inactiveFontWeight: FontWeight.w500,
                        )
                      else ...[
                        Icon(
                          item.icon,
                          size: 20,
                          color: active
                              ? kAuthGold
                              : Colors.white.withValues(alpha: 0.52),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          style: GoogleFonts.inter(
                            color: active
                                ? kAuthGold
                                : Colors.white.withValues(alpha: 0.52),
                            fontSize: 11,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

_StoryEntry? _storyEntryFromDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  _StoryWorker worker,
) {
  final data = doc.data();
  final mediaUrl = VpsMediaService.normalizeMediaUrlSync(
    (data['mediaUrl'] as String?)?.trim(),
  );
  if (mediaUrl.isEmpty) return null;

  final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ??
      (data['publishedAt'] as Timestamp?)?.toDate() ??
      DateTime.now();

  return _StoryEntry(
    id: doc.id,
    workerId: worker.id,
    mediaUrl: mediaUrl,
    kind: (data['kind'] as String?)?.trim() ?? 'story-image',
    mimeType: (data['mediaMimeType'] as String?)?.trim() ?? 'image/jpeg',
    createdAt: createdAt,
    latitude: _readCoordinate(data, ['latitude', 'storyLatitude', 'lat']),
    longitude:
        _readCoordinate(data, ['longitude', 'storyLongitude', 'lng', 'lon']),
    fileId: (data['fileId'] as String?)?.trim(),
    durationMs: (data['durationMs'] as num?)?.toInt(),
    caption: (data['caption'] as String?)?.trim(),
  );
}

_LatLng? _resolveStoryCoords(List<_StoryEntry> stories) {
  for (final story in stories.reversed) {
    if (story.latitude != null && story.longitude != null) {
      return _LatLng(story.latitude!, story.longitude!);
    }
  }
  return null;
}

Future<_LatLng?> _resolveWorkerCoords(
  String? address, {
  required String apiKey,
}) async {
  final normalized = address?.trim() ?? '';
  if (normalized.isEmpty) return null;
  return _geocodeAddress(normalized, apiKey: apiKey);
}

double? _readCoordinate(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool _isStoryStillActive(Map<String, dynamic> data, DateTime now) {
  final expiresAt = data['expiresAt'];
  if (expiresAt is Timestamp) {
    return expiresAt.toDate().isAfter(now);
  }
  if (expiresAt is String) {
    final parsed = DateTime.tryParse(expiresAt.trim());
    if (parsed != null) return parsed.isAfter(now);
  }
  if (expiresAt is int) {
    return DateTime.fromMillisecondsSinceEpoch(expiresAt).isAfter(now);
  }

  final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ??
      (data['publishedAt'] as Timestamp?)?.toDate();
  if (createdAt == null) return true;
  return createdAt.add(const Duration(hours: 24)).isAfter(now);
}

Set<String> _profileMatchKeys(String docId, Map<String, dynamic> data) {
  final keys = <String>{};

  void addValue(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isNotEmpty) keys.add(value);
  }

  addValue(docId);
  for (final key in [
    'userId',
    'uid',
    'authUid',
    'firebaseUid',
    'ownerId',
    'workerId',
    'profileId',
  ]) {
    addValue(data[key]);
  }

  return keys;
}

String? _resolveStoryOwnerId(Map<String, dynamic> data) {
  for (final key in [
    'ownerUid',
    'userId',
    'workerId',
    'authorId',
    'ownerId',
    'publisherId',
    'uid',
  ]) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _resolveWorkerName(Map<String, dynamic> data) {
  for (final key in [
    'displayName',
    'fullName',
    'username',
    'firstName',
  ]) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }

  final firstName = (data['firstName'] as String?)?.trim() ?? '';
  final lastName = (data['lastName'] as String?)?.trim() ?? '';
  final fullName =
      [firstName, lastName].where((value) => value.isNotEmpty).join(' ').trim();
  if (fullName.isNotEmpty) return fullName;
  return 'Intervenant';
}

String _resolveWorkerSpecialty(Map<String, dynamic> data) {
  final department = ((data['department'] as String?) ?? '').trim();
  final specialty = ((data['specialty'] as String?) ?? '').trim();
  final speciality = ((data['speciality'] as String?) ?? '').trim();
  final specialtiesArray = (data['specialties'] as List?)
      ?.whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList() ??
      const <String>[];
  final resolvedSpecialty = specialty.isNotEmpty
      ? specialty
      : speciality.isNotEmpty
          ? speciality
          : specialtiesArray.isNotEmpty
              ? specialtiesArray.first
              : null;

  final normalizedDept = department.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final isQualifiedLabor = normalizedDept.contains('maindoeuvrequalifiee') ||
      normalizedDept.contains('mainoeuvrequalifiee');

  if (isQualifiedLabor && resolvedSpecialty != null) return resolvedSpecialty;
  if (department.isNotEmpty) return department;
  if (resolvedSpecialty != null) return resolvedSpecialty;

  for (final key in ['role', 'jobTitle', 'maintenanceType']) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Service';
}

String? _resolveWorkerAddress(Map<String, dynamic> data) {
  for (final key in ['address', 'jobAddress', 'location', 'currentAddress']) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final nestedProfile = data['profile'];
  if (nestedProfile is Map) {
    for (final key in ['address', 'jobAddress', 'location', 'currentAddress']) {
      final value = (nestedProfile[key]?.toString() ?? '').trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

String? _readPhotoBase64(Map<String, dynamic> data) {
  for (final key in [
    'profileImageBase64',
    'photoBase64',
    'profilePhotoBase64',
    'imageBase64',
    'avatarBase64',
  ]) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

Uint8List? _decodePhoto(String? base64Value) {
  final value = base64Value?.trim() ?? '';
  if (value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}

Widget _buildWorkerPhoto({
  required String? photoUrl,
  required Uint8List? photoBytes,
  required String fallbackLabel,
}) {
  if ((photoUrl ?? '').trim().isNotEmpty) {
    return Image.network(
      photoUrl!.trim(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        if (photoBytes != null) {
          return Image.memory(photoBytes, fit: BoxFit.cover);
        }
        return _StoryFallbackAvatar(label: fallbackLabel);
      },
    );
  }
  if (photoBytes != null) {
    return Image.memory(photoBytes, fit: BoxFit.cover);
  }
  return _StoryFallbackAvatar(label: fallbackLabel);
}

class _StoryFallbackAvatar extends StatelessWidget {
  const _StoryFallbackAvatar({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181818),
      alignment: Alignment.center,
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: kAuthGold,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

bool _hasCallablePhone(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return false;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 6;
}

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

Future<_LatLng?> _geocodeAddress(
  String address, {
  required String apiKey,
}) async {
  final normalizedAddress = address.trim();
  if (normalizedAddress.isEmpty) return null;
  if (_storyGeocodeCache.containsKey(normalizedAddress)) {
    return _storyGeocodeCache[normalizedAddress];
  }

  try {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': normalizedAddress,
      'key': apiKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      _storyGeocodeCache[normalizedAddress] = null;
      return null;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') {
      _storyGeocodeCache[normalizedAddress] = null;
      return null;
    }
    final loc = (body['results'] as List).first['geometry']['location'];
    final coords =
        _LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
    _storyGeocodeCache[normalizedAddress] = coords;
    return coords;
  } catch (_) {
    _storyGeocodeCache[normalizedAddress] = null;
    return null;
  }
}

double _haversineKm(_LatLng a, _LatLng b) {
  const r = 6371.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.lat * math.pi / 180) *
          math.cos(b.lat * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(s));
}
