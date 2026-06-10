import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import 'intervenants_screen.dart';
import 'create_manager_offer_screen.dart';
import 'manager_offer_detail_screen.dart';
import 'manager_messages_screen.dart';
import 'manager_notifications_screen.dart';
import 'manager_property_route_helper.dart';
import '../services/vps_media_service.dart';
import '../widgets/unread_messages_nav_item.dart';
import 'package:lucide_icons/lucide_icons.dart';

// â”€â”€ Color constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kOffersBg = Color(0xFF070707);
const _kOffersCard = Color(0xFF111111);
const _kOffersBorder = Color(0x33D6A85A);
const _kSearchBg = Color(0xFF181818);

// â”€â”€ Data models â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OfferItem {
  const _OfferItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    this.createdAt,
    this.deadline,
    this.budget,
    this.assignedToId,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String status;
  final DateTime? createdAt;
  final DateTime? deadline;
  final double? budget;
  final String? assignedToId;

  factory _OfferItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _OfferItem(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category:
          (d['category'] as String?) ?? (d['specialty'] as String?) ?? 'autre',
      status: _normalizeManagerOfferStatus(d['status'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      deadline: (d['deadline'] as Timestamp?)?.toDate(),
      budget: ((d['budget'] ?? d['budgetAmount']) as num?)?.toDouble(),
      assignedToId:
          (d['assignedToId'] as String?) ?? (d['assignedWorkerId'] as String?),
    );
  }
}

class _WorkerOfferItem {
  const _WorkerOfferItem({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.workerDepartment,
    required this.title,
    required this.description,
    required this.category,
    required this.isActive,
    required this.isPromotion,
    required this.isFeatured,
    required this.isAvailable,
    this.photoBase64,
    this.photoUrl,
    this.price,
    this.originalRate,
    this.targetCity,
    this.targetRegion,
    this.managerLocationScope,
    this.createdAt,
  });

  final String id;
  final String workerId;
  final String workerName;
  final String workerDepartment;
  final String? photoBase64;
  final String? photoUrl;
  final String title;
  final String description;
  final String category;
  final double? price;
  final double? originalRate;
  final bool isActive;
  final bool isPromotion;
  final bool isFeatured;
  final bool isAvailable;
  final String? targetCity;
  final String? targetRegion;
  final String? managerLocationScope;
  final DateTime? createdAt;

  int? get discountPercent {
    if (originalRate != null && price != null && originalRate! > price!) {
      return ((originalRate! - price!) / originalRate! * 100).round();
    }
    return null;
  }

  String get displayDepartmentLabel => _resolveOfferDepartmentLabel(
        department: workerDepartment,
        specialtyOrCategory: category,
      );

  factory _WorkerOfferItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _WorkerOfferItem(
      id: doc.id,
      workerId: d['workerId'] as String? ?? '',
      workerName: d['workerName'] as String? ?? 'Intervenant',
      workerDepartment: d['workerDepartment'] as String? ?? '',
      photoBase64:
          (d['workerPhotoBase64'] as String?) ?? (d['photoBase64'] as String?),
      photoUrl: ((d['workerPhotoUrl'] as String?)?.trim().isNotEmpty ?? false)
          ? VpsMediaService.normalizeMediaUrlSync(
              d['workerPhotoUrl'] as String?)
          : VpsMediaService.resolveProfileImageUrl(d),
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category: (d['selectedSpecialty'] as String?) ??
          (d['category'] as String?) ??
          'autre',
      price: (d['promotionalRate'] as num?)?.toDouble() ??
          (d['regularRate'] as num?)?.toDouble() ??
          (d['price'] as num?)?.toDouble(),
      originalRate: (d['originalRate'] as num?)?.toDouble(),
      isActive: (d['status'] as String?)?.trim() == 'active' ||
          ((d['isActive'] as bool?) ?? false) ||
          ((d['visibleToManagers'] as bool?) ?? false),
      isPromotion: d['isPromotion'] as bool? ?? false,
      isFeatured: d['isFeatured'] as bool? ?? false,
      isAvailable: (d['isAvailableNow'] as bool?) ??
          (d['isAvailable'] as bool?) ??
          false,
      targetCity: (d['targetCity'] as String?)?.trim(),
      targetRegion: (d['targetRegion'] as String?)?.trim(),
      managerLocationScope: (d['managerLocationScope'] as String?)?.trim(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

String _normalizeManagerOfferStatus(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'open':
    case 'ouverte':
      return 'ouverte';
    case 'assigned':
    case 'assignee':
      return 'assignee';
    case 'completed':
    case 'terminee':
      return 'terminee';
    case 'en_cours':
      return 'en_cours';
    case 'cancelled':
    case 'annulee':
      return 'annulee';
    default:
      return 'ouverte';
  }
}

// â”€â”€ Main screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
List<String> _collectOfferFileIds(Map<String, dynamic> data) {
  final fileIds = <String>{};

  void addValue(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      fileIds.add(value);
    }
  }

  final storedIds = data['offerFileIds'];
  if (storedIds is List) {
    for (final value in storedIds) {
      addValue(value);
    }
  }

  final photos = data['photos'];
  if (photos is List) {
    for (final entry in photos) {
      if (entry is Map) {
        addValue(entry['fileId']);
      }
    }
  }

  final attachments = data['attachments'];
  if (attachments is List) {
    for (final entry in attachments) {
      if (entry is Map) {
        addValue(entry['fileId']);
      }
    }
  }

  final document = data['document'];
  if (document is Map) {
    addValue(document['fileId']);
  }

  return fileIds.toList();
}

class ManagerOffersScreen extends StatefulWidget {
  const ManagerOffersScreen({super.key});

  @override
  State<ManagerOffersScreen> createState() => _ManagerOffersScreenState();
}

class _ManagerOffersScreenState extends State<ManagerOffersScreen> {
  int _activeTab = 0;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _openCreateSheet() async {
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateManagerOfferScreen(uid: _uid ?? ''),
      ),
    );
    if (published == true && mounted) setState(() => _activeTab = 1);
  }

  void _showSoon(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffersBg,
      body: Stack(
        children: [
          Column(
            children: [
              _OffersHeader(uid: _uid ?? ''),
              const SizedBox(height: 12),
              _SegmentedTabs(
                active: _activeTab,
                onSelect: (i) => setState(() => _activeTab = i),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: IndexedStack(
                  index: _activeTab,
                  children: [
                    _WorkerOffersTab(uid: _uid ?? '', showSoon: _showSoon),
                    _MesOffresTab(
                      uid: _uid ?? '',
                      openCreate: _openCreateSheet,
                      showSoon: _showSoon,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
          if (_activeTab == 1)
            Positioned(
              bottom: 120,
              right: 20,
              child: _CreateFAB(onTap: _openCreateSheet),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _OffersBottomNav(
              onAccueil: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => buildManagerHomeScreen()),
              ),
              onAgents: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
              ),
              onMessages: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const ManagerMessagesScreen()),
              ),
              onProfil: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => buildManagerProfileScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OffersHeader extends StatelessWidget {
  const _OffersHeader({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            _ManagerAvatar(uid: uid),
            const Spacer(),
            Text(
              'Offres',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            const _BellButton(),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Manager avatar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ManagerAvatar extends StatelessWidget {
  const _ManagerAvatar({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (ctx, snap) {
        String initial = 'M';
        String? photoBase64;
        String? photoUrl;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final fn = d['firstName'] as String? ?? '';
          if (fn.isNotEmpty) initial = fn[0].toUpperCase();
          photoBase64 = d['photoBase64'] as String?;
          photoUrl = (d['photoUrl'] as String?) ?? (d['photoURL'] as String?);
        }
        final safePhotoUrl = photoUrl ?? '';
        final safePhotoBase64 = photoBase64 ?? '';
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kAuthGold, width: 1.5),
            color: const Color(0xFF1A1A1A),
          ),
          child: ClipOval(
            child: safePhotoUrl.isNotEmpty
                ? Image.network(
                    safePhotoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => safePhotoBase64.isNotEmpty
                        ? Image.memory(
                            base64Decode(safePhotoBase64),
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Text(
                              initial,
                              style: GoogleFonts.inter(
                                color: kAuthGold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  )
                : photoBase64 != null && photoBase64.isNotEmpty
                    ? Image.memory(base64Decode(photoBase64), fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          initial,
                          style: GoogleFonts.inter(
                            color: kAuthGold,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
          ),
        );
      },
    );
  }
}

// â”€â”€ Bell button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _BellButton extends StatelessWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ManagerNotificationsScreen(),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1A),
              border: Border.all(
                  color: kAuthGold.withValues(alpha: 0.35), width: 1),
            ),
            child: Icon(
              LucideIcons.bell,
              color: Colors.white.withValues(alpha: 0.80),
              size: 18,
            ),
          ),
          const Positioned(
            top: 0,
            right: 0,
            child: UnreadMessagesDot(
              size: 9,
              color: Color(0xFFFF3B30),
              borderColor: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Segmented tabs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.active, required this.onSelect});
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: _kOffersCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kOffersBorder),
        ),
        child: Row(
          children: [
            _TabItem(
              label: 'Offres des intervenants',
              isActive: active == 0,
              onTap: () => onSelect(0),
            ),
            _TabItem(
              label: 'Mes offres',
              isActive: active == 1,
              onTap: () => onSelect(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isActive ? kAuthGold : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isActive ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ "Mes offres" tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MesOffresTab extends StatefulWidget {
  const _MesOffresTab({
    required this.uid,
    required this.openCreate,
    required this.showSoon,
  });

  final String uid;
  final VoidCallback openCreate;
  final void Function(String) showSoon;

  @override
  State<_MesOffresTab> createState() => _MesOffresTabState();
}

class _MesOffresTabState extends State<_MesOffresTab> {
  String _search = '';
  String _activeStatus = 'toutes';
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) {
      _stream = const Stream.empty();
    } else {
      _stream = FirebaseFirestore.instance
          .collection('offers')
          .where('createdByManagerId', isEqualTo: widget.uid)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _SkeletonList();
        }

        final allItems = snap.hasData
            ? snap.data!.docs.map(_OfferItem.fromDoc).toList()
            : <_OfferItem>[];
        allItems.sort((a, b) {
          final aCreatedAt = a.createdAt;
          final bCreatedAt = b.createdAt;
          if (aCreatedAt == null && bCreatedAt == null) return 0;
          if (aCreatedAt == null) return 1;
          if (bCreatedAt == null) return -1;
          return bCreatedAt.compareTo(aCreatedAt);
        });

        final filtered = allItems.where((o) {
          if (_activeStatus != 'toutes' && o.status != _activeStatus) {
            return false;
          }
          if (_search.isNotEmpty &&
              !o.title.toLowerCase().contains(_search.toLowerCase()) &&
              !o.description.toLowerCase().contains(_search.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SearchAndFilter(
                value: _search,
                onChanged: (v) => setState(() => _search = v),
                placeholder: 'Rechercher une offre...',
              ),
            ),
            const SizedBox(height: 4),
            _StatusChips(
              active: _activeStatus,
              onSelect: (s) => setState(() => _activeStatus = s),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyOffersState(onCreateTap: widget.openCreate)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _OfferCard(
                        item: filtered[i],
                        uid: widget.uid,
                        showSoon: widget.showSoon,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// â”€â”€ Search and filter row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SearchAndFilter extends StatelessWidget {
  const _SearchAndFilter({
    required this.value,
    required this.onChanged,
    this.placeholder = 'Rechercher...',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: _kSearchBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kOffersBorder),
            ),
            child: TextField(
              onChanged: onChanged,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: Colors.white.withValues(alpha: 0.50),
                  size: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _kSearchBg,
            shape: BoxShape.circle,
            border: Border.all(color: _kOffersBorder),
          ),
          child: Icon(
            LucideIcons.slidersHorizontal,
            color: Colors.white.withValues(alpha: 0.70),
            size: 18,
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Status chips â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.active, required this.onSelect});
  final String active;
  final ValueChanged<String> onSelect;

  static const _chips = [
    ('toutes', 'Toutes'),
    ('ouverte', 'Ouvertes'),
    ('en_cours', 'En cours'),
    ('assignee', 'AssignÃ©es'),
    ('terminee', 'TerminÃ©es'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, label) = _chips[i];
          final isActive = active == key;
          return GestureDetector(
            onTap: () => onSelect(key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? kAuthGold : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? kAuthGold : _kOffersBorder,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: isActive
                      ? Colors.black
                      : Colors.white.withValues(alpha: 0.70),
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// â”€â”€ Offer card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.item,
    required this.uid,
    required this.showSoon,
  });

  final _OfferItem item;
  final String uid;
  final void Function(String) showSoon;

  static IconData _iconFor(String category) {
    switch (category) {
      case 'plomberie':
        return LucideIcons.droplets;
      case 'electricite':
        return LucideIcons.zap;
      case 'peinture':
        return LucideIcons.paintbrush;
      case 'menuiserie':
        return LucideIcons.hammer;
      default:
        return LucideIcons.wrench;
    }
  }

  static String _labelFor(String category) {
    switch (category) {
      case 'plomberie':
        return 'Plomberie';
      case 'electricite':
        return 'Ã‰lectricitÃ©';
      case 'peinture':
        return 'Peinture';
      case 'menuiserie':
        return 'Menuiserie';
      default:
        return 'Autre';
    }
  }

  static Color _colorFor(String status) {
    switch (status) {
      case 'ouverte':
        return const Color(0xFF22C55E);
      case 'en_cours':
        return kAuthGold;
      case 'assignee':
        return const Color(0xFF3B82F6);
      default:
        return Colors.white;
    }
  }

  static String _statusLabelFor(String status) {
    switch (status) {
      case 'ouverte':
        return 'Ouverte';
      case 'en_cours':
        return 'En cours';
      case 'assignee':
        return 'AssignÃ©e';
      case 'terminee':
        return 'TerminÃ©e';
      default:
        return status;
    }
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _colorFor(item.status);
    return GestureDetector(
      onLongPress: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _OfferActionSheet(item: item),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kOffersCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kOffersBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kOffersBorder),
              ),
              child: Icon(_iconFor(item.category), color: kAuthGold, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.50)),
                        ),
                        child: Text(
                          _statusLabelFor(item.status),
                          style: GoogleFonts.inter(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _labelFor(item.category),
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.budget != null) ...[
                        Icon(LucideIcons.dollarSign,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.50)),
                        const SizedBox(width: 2),
                        Text(
                          '${item.budget!.toStringAsFixed(0)} DZD',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (item.deadline != null) ...[
                        Icon(LucideIcons.calendar,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.50)),
                        const SizedBox(width: 2),
                        Text(
                          _fmtDate(item.deadline),
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        _fmtDate(item.createdAt),
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.40),
                          fontSize: 11,
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
    );
  }
}

// â”€â”€ Offer action sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OfferActionSheet extends StatelessWidget {
  const _OfferActionSheet({required this.item});
  final _OfferItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kOffersBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              item.title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Que voulez-vous faire ?',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _ActionTile(
                  icon: LucideIcons.pencil,
                  label: 'Modifier',
                  color: kAuthGold,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Modification bientÃ´t disponible',
                          style: GoogleFonts.inter(color: Colors.white),
                        ),
                        backgroundColor: const Color(0xFF1A1A1A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _ActionTile(
                  icon: LucideIcons.trash2,
                  label: 'Supprimer dÃ©finitivement',
                  color: const Color(0xFFEF4444),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final ref = FirebaseFirestore.instance
                          .collection('offers')
                          .doc(item.id);
                      final snapshot = await ref.get();
                      final data = snapshot.data() ?? const <String, dynamic>{};
                      final fileIds = _collectOfferFileIds(data);
                      await ref.delete();
                      if (fileIds.isNotEmpty) {
                        await VpsMediaService.deleteFiles(fileIds);
                      }
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ "Offres des intervenants" tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _WorkerOffersTab extends StatefulWidget {
  const _WorkerOffersTab({required this.uid, required this.showSoon});
  final String uid;
  final void Function(String) showSoon;

  @override
  State<_WorkerOffersTab> createState() => _WorkerOffersTabState();
}

class _WorkerOffersTabState extends State<_WorkerOffersTab> {
  String _condoName = '';
  String _condoLocation = '';
  String _activeChip = 'toutes';
  bool _condoLoading = true;
  Stream<QuerySnapshot> _stream = const Stream.empty();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (widget.uid.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('hotels')
            .where('ownerId', isEqualTo: widget.uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty && mounted) {
          final d = snap.docs.first.data();
          setState(() {
            _condoName = d['name'] as String? ?? '';
            _condoLocation = d['location'] as String? ?? '';
          });
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _stream = FirebaseFirestore.instance
              .collection('worker_offers')
              .orderBy('createdAt', descending: true)
              .snapshots();
        });
      }
    }
    if (mounted) setState(() => _condoLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _OfferFilterChips(
          active: _activeChip,
          onSelect: (s) => setState(() => _activeChip = s),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _stream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting ||
                  _condoLoading) {
                return const _SkeletonList();
              }
              final allItems = snap.hasData
                  ? snap.data!.docs.map(_WorkerOfferItem.fromDoc).toList()
                  : <_WorkerOfferItem>[];
              return _WorkerOffersBody(
                items: allItems,
                activeChip: _activeChip,
                condoName: _condoName,
                condoLocation: _condoLocation,
                showSoon: widget.showSoon,
              );
            },
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Create FAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _CreateFAB extends StatelessWidget {
  const _CreateFAB({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: kAuthGold,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kAuthGold.withValues(alpha: 0.40),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(LucideIcons.plus, color: Colors.black, size: 26),
      ),
    );
  }
}

// â”€â”€ Empty states â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EmptyOffersState extends StatelessWidget {
  const _EmptyOffersState({required this.onCreateTap});
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _kOffersCard,
                shape: BoxShape.circle,
                border: Border.all(color: _kOffersBorder),
              ),
              child: const Icon(LucideIcons.clipboardList,
                  color: kAuthGold, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Aucune offre crÃ©Ã©e',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'CrÃ©ez votre premiÃ¨re offre pour trouver\nle bon intervenant.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onCreateTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: kAuthGold,
                side: const BorderSide(color: kAuthGold),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'CrÃ©er une offre',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Skeleton list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 3,
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 100,
      decoration: BoxDecoration(
        color: _kOffersCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kOffersBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(5),
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

// â”€â”€ Bottom nav â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OffersBottomNav extends StatelessWidget {
  const _OffersBottomNav({
    required this.onAccueil,
    required this.onAgents,
    required this.onMessages,
    required this.onProfil,
  });

  final VoidCallback onAccueil;
  final VoidCallback onAgents;
  final VoidCallback onMessages;
  final VoidCallback onProfil;

  @override
  Widget build(BuildContext context) {
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
            _OffersNavItem(
              icon: LucideIcons.home,
              label: 'Accueil',
              isActive: false,
              onTap: onAccueil,
            ),
            _OffersNavItem(
              icon: LucideIcons.users,
              label: 'Agents',
              isActive: false,
              onTap: onAgents,
            ),
            const _OffersNavItem(
              icon: LucideIcons.clipboardList,
              label: 'Offres',
              isActive: true,
            ),
            UnreadMessagesNavItem(
              isActive: false,
              onTap: onMessages,
              activeColor: kAuthGold,
              inactiveColor: Colors.white.withValues(alpha: 0.65),
              dotColor: const Color(0xFFFF3B30),
            ),
            _OffersNavItem(
              icon: LucideIcons.user,
              label: 'Profil',
              isActive: false,
              onTap: onProfil,
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersNavItem extends StatelessWidget {
  const _OffersNavItem({
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
                  isActive ? kAuthGold : Colors.white.withValues(alpha: 0.65),
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

// â”€â”€ Worker Offers Tab Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

IconData _iconFor(String category) {
  switch (category) {
    case 'plomberie':
      return LucideIcons.droplets;
    case 'electricite':
      return LucideIcons.zap;
    case 'peinture':
      return LucideIcons.paintbrush;
    case 'menuiserie':
      return LucideIcons.hammer;
    default:
      return LucideIcons.wrench;
  }
}

// â”€â”€ Offer Filter Chips â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OfferFilterChips extends StatelessWidget {
  const _OfferFilterChips({
    required this.active,
    required this.onSelect,
  });

  final String active;
  final void Function(String) onSelect;

  static const _chips = [
    ('toutes', 'Toutes', LucideIcons.layoutGrid),
    ('maintenance', 'Maintenance', LucideIcons.wrench),
    ('main_oeuvre', 'Main-d\'oeuvre', LucideIcons.hammer),
    ('chambres', 'Chambres', LucideIcons.bed),
    ('houseman', 'Houseman', LucideIcons.building),
    ('concierge', 'Concierge', LucideIcons.key),
    ('menage', 'MÃ©nage', LucideIcons.sparkles),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _chips.length,
        itemBuilder: (_, i) {
          final (key, label, icon) = _chips[i];
          final isActive = active == key;
          return GestureDetector(
            onTap: () => onSelect(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              height: 38,
              decoration: BoxDecoration(
                color: isActive ? kAuthGold : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
                border: isActive ? null : Border.all(color: _kOffersBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isActive
                        ? Colors.black
                        : Colors.white.withValues(alpha: 0.70),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.black
                          : Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// â”€â”€ Worker Offers Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _WorkerOffersBody extends StatelessWidget {
  const _WorkerOffersBody({
    required this.items,
    required this.activeChip,
    required this.condoName,
    required this.condoLocation,
    required this.showSoon,
  });

  final List<_WorkerOfferItem> items;
  final String activeChip;
  final String condoName;
  final String condoLocation;
  final void Function(String) showSoon;

  void _openOfferDetail(BuildContext context, _WorkerOfferItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManagerOfferDetailScreen(
          workerId: item.workerId,
          workerName: item.workerName,
          workerDepartment: item.workerDepartment,
          workerDisplayLabel: item.displayDepartmentLabel,
          title: item.title,
          description: item.description,
          category: item.category,
          photoBase64: item.photoBase64,
          photoUrl: item.photoUrl,
          price: item.price,
          originalRate: item.originalRate,
          targetCity: item.targetCity,
          targetRegion: item.targetRegion,
          isAvailable: item.isAvailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = items.where((o) {
      if (!o.isActive) return false;
      if (!_matchesManagerLocation(o, condoLocation)) return false;
      if (activeChip != 'toutes') {
        final cat = _normalizeToken(o.category);
        final dept = _normalizeToken(o.workerDepartment);
        if (!_matchesDepartmentChip(activeChip, cat, dept)) return false;
      }
      return true;
    }).toList();

    final promoItems = filtered.where((o) => o.isPromotion).toList();
    final regularItems = filtered.where((o) => !o.isPromotion).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _SectionRow(
            title: 'Promotions',
            action: 'Voir toutes',
            hasChevron: true,
            onTap: () => showSoon('Toutes les promotions bientÃ´t disponibles.'),
          ),
          if (promoItems.isEmpty)
            const _EmptyPromoState()
          else
            _PromotionsCarousel(items: promoItems, showSoon: showSoon),
          const SizedBox(height: 16),
          _SectionRow(
            title: 'Offres disponibles',
            action: 'Trier â†“',
            hasChevron: false,
            onTap: () => showSoon('Options de tri bientÃ´t disponibles.'),
          ),
          if (regularItems.isEmpty)
            _EmptyRegularOffresState(condoName: condoName)
          else
            ...regularItems.map(
              (item) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _RegularOfferCard(
                  item: item,
                  showSoon: (_) => _openOfferDetail(context, item),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

bool _matchesManagerLocation(_WorkerOfferItem item, String condoLocation) {
  final cityRegion = _cityRegionFromLocation(condoLocation);
  final city = _normalizeToken(cityRegion.$1);
  final region = _normalizeToken(cityRegion.$2);
  final itemCity = _normalizeToken(item.targetCity);
  final itemRegion = _normalizeToken(item.targetRegion);
  final scope = _normalizeToken(item.managerLocationScope);

  if (scope.isEmpty || scope == 'same_city') {
    if (city.isEmpty || itemCity.isEmpty) return true;
    return city == itemCity;
  }
  if (scope == 'same_region') {
    if (region.isEmpty || itemRegion.isEmpty) return true;
    return region == itemRegion;
  }
  return true;
}

(String, String) _cityRegionFromLocation(String raw) {
  final parts = raw
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return (parts[parts.length - 2], parts.last);
  }
  if (parts.length == 1) {
    return (parts.first, '');
  }
  return ('', '');
}

bool _matchesDepartmentChip(String chip, String cat, String dept) {
  switch (chip) {
    case 'maintenance':
      return cat.contains('maintenance') || dept.contains('maintenance');
    case 'main_oeuvre':
      return cat.contains('main') ||
          dept.contains('main') ||
          cat.contains('qualifie') ||
          dept.contains('qualifie');
    case 'chambres':
      return cat.contains('chambre') ||
          dept.contains('chambre') ||
          cat.contains('prepos') ||
          dept.contains('prepos');
    case 'houseman':
      return cat.contains('houseman') || dept.contains('houseman');
    case 'concierge':
      return cat.contains('concierge') ||
          dept.contains('concierge') ||
          cat.contains('reception') ||
          dept.contains('reception');
    case 'menage':
      return cat.contains('menage') ||
          dept.contains('menage') ||
          cat.contains('nettoyage') ||
          dept.contains('nettoyage');
    default:
      return true;
  }
}

String _normalizeToken(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã¨', 'e')
      .replaceAll('Ãª', 'e')
      .replaceAll('Ã ', 'a')
      .replaceAll('Ã¹', 'u')
      .replaceAll('Ã´', 'o')
      .replaceAll('Ã®', 'i');
}

// â”€â”€ Promotions Carousel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
bool _isQualifiedLaborDepartment(String? department) {
  final normalized = _normalizeToken(department)
      .replaceAll('Å“', 'oe')
      .replaceAll("'", '')
      .replaceAll('-', '')
      .replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('maindoeuvrequalifiee') ||
      normalized.contains('maindoeuvrequalifie');
}

String _resolveOfferDepartmentLabel({
  required String? department,
  required String? specialtyOrCategory,
}) {
  final trimmedSpecialty = (specialtyOrCategory ?? '').trim();
  if (_isQualifiedLaborDepartment(department) && trimmedSpecialty.isNotEmpty) {
    return trimmedSpecialty;
  }

  final trimmedDepartment = (department ?? '').trim();
  if (trimmedDepartment.isNotEmpty) {
    return trimmedDepartment;
  }

  return trimmedSpecialty;
}

class _PromotionsCarousel extends StatefulWidget {
  const _PromotionsCarousel({required this.items, required this.showSoon});

  final List<_WorkerOfferItem> items;
  final void Function(String) showSoon;

  @override
  State<_PromotionsCarousel> createState() => _PromotionsCarouselState();
}

class _PromotionsCarouselState extends State<_PromotionsCarousel> {
  late final PageController _pageCtrl;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.76, initialPage: 0);
    _pageCtrl.addListener(() {
      if (mounted) setState(() => _page = _pageCtrl.page ?? 0);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 340,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.items.length,
            itemBuilder: (_, i) {
              final isCenter = (_page - i).abs() < 0.5;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                margin: EdgeInsets.only(
                  top: isCenter ? 0 : 18,
                  bottom: 4,
                  left: 6,
                  right: 6,
                ),
                child: _PromoCard(
                  item: widget.items[i],
                  isCenter: isCenter,
                  onTap: () => widget
                      .showSoon('DÃ©tails de l\'offre bientÃ´t disponibles.'),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _PageDots(count: widget.items.length, page: _page),
        const SizedBox(height: 8),
      ],
    );
  }
}

// â”€â”€ Promo Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.item,
    required this.isCenter,
    required this.onTap,
  });

  final _WorkerOfferItem item;
  final bool isCenter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kOffersCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCenter ? kAuthGold : _kOffersBorder,
            width: isCenter ? 1.5 : 1.0,
          ),
          boxShadow: isCenter
              ? [
                  BoxShadow(
                    color: kAuthGold.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Photo area
            SizedBox(
              height: 180,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Background: photo or initial letter
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: item.photoUrl != null && item.photoUrl!.isNotEmpty
                        ? Image.network(
                            item.photoUrl!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => item.photoBase64 !=
                                    null
                                ? Image.memory(
                                    base64Decode(item.photoBase64!),
                                    width: double.infinity,
                                    height: 180,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _InitialBg(
                                      name: item.workerName,
                                      height: 180,
                                    ),
                                  )
                                : _InitialBg(
                                    name: item.workerName,
                                    height: 180,
                                  ),
                          )
                        : item.photoBase64 != null
                            ? Image.memory(
                                base64Decode(item.photoBase64!),
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _InitialBg(
                                  name: item.workerName,
                                  height: 180,
                                ),
                              )
                            : _InitialBg(name: item.workerName, height: 155),
                  ),
                  // Gradient overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.70),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Promo badge top-left
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _PromoBadge(isFeatured: item.isFeatured),
                  ),
                  // Discount badge top-right
                  if (item.discountPercent != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _DiscountBadge(percent: item.discountPercent!),
                    ),
                  // Category circle â€” overlaps bottom edge
                  Positioned(
                    bottom: -22,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _CategoryCircle(category: item.category),
                    ),
                  ),
                ],
              ),
            ),
            // Info section
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
              child: Column(
                children: [
                  Text(
                    item.workerName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.displayDepartmentLabel,
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.originalRate != null) ...[
                        Text(
                          '${item.originalRate!.toStringAsFixed(0)} \$/h',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (item.price != null)
                        Text(
                          '${item.price!.toStringAsFixed(0)} \$/h',
                          style: GoogleFonts.inter(
                            color: kAuthGold,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (item.isAvailable) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Disponible',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF22C55E),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Initial letter background for avatars
class _InitialBg extends StatelessWidget {
  const _InitialBg({required this.name, required this.height});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: double.infinity,
      height: height,
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Promo Badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.isFeatured});

  final bool isFeatured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kOffersBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFeatured ? LucideIcons.crown : LucideIcons.tag,
            color: kAuthGold,
            size: 11,
          ),
          const SizedBox(width: 4),
          Text(
            isFeatured ? 'Top offre' : 'Promotion',
            style: GoogleFonts.inter(
              color: kAuthGold,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Discount Badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '-$percent%',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// â”€â”€ Category Circle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        shape: BoxShape.circle,
        border: Border.all(color: kAuthGold, width: 2),
      ),
      child: Icon(_iconFor(category), color: kAuthGold, size: 18),
    );
  }
}

// â”€â”€ Page Dots â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page});

  final int count;
  final double page;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = (page - i).abs() < 0.5;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isActive ? 20 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? kAuthGold : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// â”€â”€ Section Row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.title,
    required this.action,
    required this.onTap,
    this.hasChevron = true,
  });

  final String title;
  final String action;
  final VoidCallback onTap;
  final bool hasChevron;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Row(
              children: [
                Text(
                  action,
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasChevron)
                  const Icon(
                    LucideIcons.chevronRight,
                    color: kAuthGold,
                    size: 16,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Regular Offer Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _RegularOfferCard extends StatelessWidget {
  const _RegularOfferCard({
    required this.item,
    required this.showSoon,
  });

  final _WorkerOfferItem item;
  final void Function(String) showSoon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showSoon('DÃ©tails de l\'offre bientÃ´t disponibles.'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kOffersCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kOffersBorder),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _kOffersBorder, width: 1.5),
              ),
              child: ClipOval(
                child: item.photoUrl != null && item.photoUrl!.isNotEmpty
                    ? Image.network(
                        item.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => item.photoBase64 != null
                            ? Image.memory(
                                base64Decode(item.photoBase64!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _AvatarInitial(name: item.workerName),
                              )
                            : _AvatarInitial(name: item.workerName),
                      )
                    : item.photoBase64 != null
                        ? Image.memory(
                            base64Decode(item.photoBase64!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _AvatarInitial(name: item.workerName),
                          )
                        : _AvatarInitial(name: item.workerName),
              ),
            ),
            const SizedBox(width: 12),
            // Center info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.workerName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.displayDepartmentLabel,
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.title.isNotEmpty ? item.title : item.description,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.isAvailable) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Disponible',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF22C55E),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: price + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.price != null
                      ? '${item.price!.toStringAsFixed(0)} \$/h'
                      : 'Gratuit',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  LucideIcons.chevronRight,
                  color: Colors.white.withValues(alpha: 0.50),
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Small avatar initial widget for list cards
class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Bottom Info Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€ Empty States â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EmptyPromoState extends StatelessWidget {
  const _EmptyPromoState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.tag, color: kAuthGold, size: 36),
            const SizedBox(height: 10),
            Text(
              'Aucune promotion disponible',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aucune offre promotionnelle pour le moment.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRegularOffresState extends StatelessWidget {
  const _EmptyRegularOffresState({required this.condoName});

  final String condoName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.briefcase, color: kAuthGold, size: 36),
            const SizedBox(height: 10),
            Text(
              'Aucune offre disponible',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (condoName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Aucune offre active pour $condoName.',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
