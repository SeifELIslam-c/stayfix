// ignore_for_file: unused_element, unused_field

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/screens/intervenants_screen.dart';
import 'package:hotel_lux_os/screens/manager_chat_thread_screen.dart';
import 'package:hotel_lux_os/screens/manager_offers_screen.dart';
import 'package:hotel_lux_os/screens/manager_property_route_helper.dart';
import 'package:hotel_lux_os/services/vps_media_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

// -- Color constants -----------------------------------------------------------
const _kMsgBg = Color(0xFF070707);
const _kMsgCard = Color(0xFF111111);
const _kMsgCardBorder = Color(0x33D6A85A);
const _kOrangeDot = Color(0xFFFF6B35);
const _kGreenDot = Color(0xFF22C55E);

// -----------------------------------------------------------------------------
// Data models
// -----------------------------------------------------------------------------

class _ConvItem {
  const _ConvItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.lastMessage,
    required this.unread,
    required this.isAvailable,
    this.lastAt,
    this.workerId,
    this.photoBase64,
    this.photoUrl,
    this.memberPhotoBase64s = const [],
  });

  final String id;
  final String type; // 'intervenant' | 'team' | 'system' | 'property'
  final String title;
  final String subtitle;
  final String lastMessage;
  final int unread;
  final bool isAvailable;
  final DateTime? lastAt;
  final String? workerId;
  final String? photoBase64;
  final String? photoUrl;
  final List<String> memberPhotoBase64s;

  _ConvItem copyWith({
    String? photoBase64,
    String? photoUrl,
    String? subtitle,
    bool? isAvailable,
    List<String>? memberPhotoBase64s,
  }) =>
      _ConvItem(
        id: id,
        type: type,
        title: photoBase64 != null ? title : title,
        subtitle: subtitle ?? this.subtitle,
        lastMessage: lastMessage,
        unread: unread,
        isAvailable: isAvailable ?? this.isAvailable,
        lastAt: lastAt,
        workerId: workerId,
        photoBase64: photoBase64 ?? this.photoBase64,
        photoUrl: photoUrl ?? this.photoUrl,
        memberPhotoBase64s: memberPhotoBase64s ?? this.memberPhotoBase64s,
      );
}

class _WorkerCache {
  final String? username;
  final String? subtitle;
  final String? photoBase64;
  final String? photoUrl;
  final bool isAvailable;
  _WorkerCache(
      {this.username,
      this.subtitle,
      this.photoBase64,
      this.photoUrl,
      this.isAvailable = false});
}

// -----------------------------------------------------------------------------
// Main screen
// -----------------------------------------------------------------------------

class ManagerMessagesScreen extends StatefulWidget {
  const ManagerMessagesScreen({super.key});

  @override
  State<ManagerMessagesScreen> createState() => _ManagerMessagesScreenState();
}

class _ManagerMessagesScreenState extends State<ManagerMessagesScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final String _filter = 'tous';
  final Map<String, _WorkerCache> _workerCache = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showSoon(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      ),
    );
  }

  Future<_WorkerCache?> _fetchWorker(String workerId) async {
    if (_workerCache.containsKey(workerId)) return _workerCache[workerId];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(workerId)
          .get();
      if (!doc.exists) return null;
      final d = doc.data()!;
      String? name;
      for (final k in ['username', 'fullName', 'displayName', 'firstName']) {
        final v = (d[k] as String?)?.trim();
        if (v != null && v.isNotEmpty) {
          name = v;
          break;
        }
      }
      String? photo;
      String? photoUrl;
      photoUrl = VpsMediaService.resolveProfileImageUrl(d);
      for (final k in [
        'photoBase64',
        'profilePhotoBase64',
        'imageBase64',
        'avatarBase64'
      ]) {
        final v = (d[k] as String?)?.trim();
        if (v != null && v.isNotEmpty) {
          photo = v;
          break;
        }
      }
      final department = (d['department'] as String?)?.trim();
      final avail = d['isAvailable'] as bool? ?? false;
      String? specialty;
      for (final key in ['specialty', 'speciality']) {
        final value = (d[key] as String?)?.trim();
        if (value != null && value.isNotEmpty) {
          specialty = value;
          break;
        }
      }
      if (specialty == null) {
        final list = d['specialties'];
        if (list is List) {
          for (final item in list) {
            final value = item?.toString().trim() ?? '';
            if (value.isNotEmpty) {
              specialty = value;
              break;
            }
          }
        }
      }
      final cache = _WorkerCache(
        username: name,
        subtitle: _resolveWorkerSubtitle(
          department: department,
          specialty: specialty,
          fallbackRole: (d['role'] as String?)?.trim(),
        ),
        photoBase64: photo,
        photoUrl: photoUrl,
        isAvailable: avail,
      );
      _workerCache[workerId] = cache;
      return cache;
    } catch (_) {
      return null;
    }
  }

  List<_ConvItem> _applyFilters(List<_ConvItem> items) {
    return items;
  }

  _ConvItem _convFromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc, String uid) {
    final d = doc.data() ?? {};
    final type = (d['type'] as String?) ?? 'intervenant';
    final title = (d['title'] as String?) ?? '';
    final lastMsg = (d['lastMessage'] as String?) ?? '';
    final ts = d['lastMessageAt'];
    DateTime? lastAt;
    if (ts is Timestamp) lastAt = ts.toDate();
    final unreadMap = d['unreadBy'];
    int unread = 0;
    if (unreadMap is Map) {
      final v = unreadMap[uid];
      if (v is int) unread = v;
    }
    final workerId = (d['workerId'] as String?)?.trim();
    final memberPhotos = ((d['memberPhotoBase64s'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();

    String subtitle;
    switch (type) {
      case 'system':
        subtitle = 'Notification système';
        break;
      case 'team':
        final memberCount = d['memberCount'];
        subtitle =
            memberCount != null ? 'Groupe · $memberCount membres' : 'Groupe';
        break;
      case 'property':
        subtitle = 'Communication';
        break;
      default:
        subtitle = (d['subtitle'] as String?) ?? '';
    }

    return _ConvItem(
      id: doc.id,
      type: type,
      title: title,
      subtitle: subtitle,
      lastMessage: lastMsg,
      unread: unread,
      isAvailable: false,
      lastAt: lastAt,
      workerId: workerId,
      photoUrl: VpsMediaService.resolveProfileImageUrl(d),
      memberPhotoBase64s: memberPhotos,
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } else if (diff.inDays == 1) {
      return 'Hier';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    }
  }

  void _openCompose() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        onContactIntervenant: () {
          Navigator.pop(context);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
          );
        },
        onCreateGroup: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _CreateGroupSheet(
              managerUid: FirebaseAuth.instance.currentUser!.uid,
            ),
          );
        },
      ),
    );
  }

  void _showConvActions(BuildContext context, _ConvItem conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConvActionSheet(
        conv: conv,
        onBlock: () async {
          Navigator.pop(context);
          try {
            await FirebaseFirestore.instance
                .collection('conversations')
                .doc(conv.id)
                .update({
              'blockedBy': FieldValue.arrayUnion(
                  [FirebaseAuth.instance.currentUser!.uid]),
            });
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Utilisateur bloqué.',
                  style: GoogleFonts.inter(color: Colors.white)),
              backgroundColor: const Color(0xFF1A1A1A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            ));
          } catch (_) {}
        },
        onDelete: () async {
          Navigator.pop(context);
          try {
            final ref = FirebaseFirestore.instance
                .collection('conversations')
                .doc(conv.id);
            // Delete all messages in subcollection first
            final msgs = await ref.collection('messages').get();
            final fileIds = <String>{};
            for (final doc in msgs.docs) {
              final data = doc.data();
              final messageFileIds = data['fileIds'];
              if (messageFileIds is List) {
                for (final id in messageFileIds) {
                  final value = id?.toString().trim() ?? '';
                  if (value.isNotEmpty) fileIds.add(value);
                }
              }
              for (final key in ['imageFileId', 'audioFileId']) {
                final value = (data[key] as String?)?.trim() ?? '';
                if (value.isNotEmpty) fileIds.add(value);
              }
            }
            if (fileIds.isNotEmpty) {
              await VpsMediaService.deleteFiles(fileIds.toList());
            }
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in msgs.docs) {
              batch.delete(doc.reference);
            }
            batch.delete(ref);
            await batch.commit();
          } catch (_) {}
        },
      ),
    );
  }

  // -- Build -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const AuthScreen();
    final uid = user.uid;

    return Scaffold(
      backgroundColor: _kMsgBg,
      body: Stack(
        children: [
          // -- Main scrollable content -------------------------------------
          Column(
            children: [
              // Header
              _MsgHeader(uid: uid),
              const SizedBox(height: 14),
              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SearchRow(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  onFilterTap: () =>
                      _showSoon('Filtres avancés bientôt disponibles.'),
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox.shrink(),
              const SizedBox(height: 16),
              // Section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _conversationsStream(uid),
                  builder: (ctx, snap) {
                    final items = _parseItems(snap, uid);
                    final totalUnread =
                        items.fold<int>(0, (s, c) => s + c.unread);
                    return _SectionHeader(unreadCount: totalUnread);
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Conversation list
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _conversationsStream(uid),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const _SkeletonList();
                    }
                    final items = _applyFilters(_parseItems(snap, uid));
                    if (items.isEmpty) {
                      return _EmptyConvsState(
                        onContactIntervenant: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const IntervenantsScreen()),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final conv = items[i];
                        return FutureBuilder<_ConvItem>(
                          future: _enrichConv(conv),
                          initialData: conv,
                          builder: (ctx, snap) {
                            final c = snap.data ?? conv;
                            return _ConvCard(
                              conv: c,
                              timeLabel: _formatTime(c.lastAt),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ManagerChatThreadScreen(
                                    conversationId: c.id,
                                    title: c.title.isEmpty
                                        ? 'Sans titre'
                                        : c.title,
                                    subtitle: c.subtitle,
                                    avatarUrl: c.photoUrl,
                                    avatarBase64: c.photoBase64,
                                    isAvailable: c.isAvailable,
                                  ),
                                ),
                              ),
                              onLongPress: () => _showConvActions(context, c),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          // -- Floating compose button -------------------------------------
          Positioned(
            bottom: 120,
            right: 20,
            child: _ComposeFab(onTap: _openCompose),
          ),
          // -- Bottom nav -------------------------------------------------
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _MsgBottomNav(
              onAccueil: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => buildManagerHomeScreen()),
              ),
              onAgents: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const IntervenantsScreen()),
              ),
              onOffres: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ManagerOffersScreen()),
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _conversationsStream(String uid) {
    try {
      return FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .snapshots();
    } catch (_) {
      return const Stream.empty();
    }
  }

  List<_ConvItem> _parseItems(
      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap, String uid) {
    if (!snap.hasData) return [];
    final items = snap.data!.docs.map((d) => _convFromDoc(d, uid)).toList();
    items.sort((a, b) {
      final aTime = a.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<_ConvItem> _enrichConv(_ConvItem conv) async {
    if (conv.type != 'intervenant' || conv.workerId == null) return conv;
    final cache = await _fetchWorker(conv.workerId!);
    if (cache == null) return conv;
    return _ConvItem(
      id: conv.id,
      type: conv.type,
      title: cache.username ?? conv.title,
      subtitle: cache.subtitle ?? conv.subtitle,
      lastMessage: conv.lastMessage,
      unread: conv.unread,
      isAvailable: cache.isAvailable,
      lastAt: conv.lastAt,
      workerId: conv.workerId,
      photoBase64: cache.photoBase64 ?? conv.photoBase64,
      photoUrl: cache.photoUrl ?? conv.photoUrl,
    );
  }
}

bool _isQualifiedLaborDepartment(String? department) {
  final normalized = (department ?? '')
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('maindoeuvrequalifie');
}

String? _resolveWorkerSubtitle({
  required String? department,
  required String? specialty,
  required String? fallbackRole,
}) {
  final trimmedSpecialty = (specialty ?? '').trim();
  if (_isQualifiedLaborDepartment(department) && trimmedSpecialty.isNotEmpty) {
    return trimmedSpecialty;
  }

  final trimmedDepartment = (department ?? '').trim();
  if (trimmedDepartment.isNotEmpty) {
    return trimmedDepartment;
  }

  final trimmedRole = (fallbackRole ?? '').trim();
  if (trimmedRole.isNotEmpty) {
    return trimmedRole;
  }

  return null;
}

String? _resolveSpecialtyValue(Map<String, dynamic> data) {
  for (final key in ['specialty', 'speciality']) {
    final value = (data[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  final list = data['specialties'];
  if (list is List) {
    for (final item in list) {
      final value = item?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
  }

  return null;
}

// -----------------------------------------------------------------------------
// _MsgHeader
// -----------------------------------------------------------------------------

class _MsgHeader extends StatelessWidget {
  const _MsgHeader({required this.uid});
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
              'Messages',
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

// -----------------------------------------------------------------------------
// _ManagerAvatar
// -----------------------------------------------------------------------------

class _ManagerAvatar extends StatelessWidget {
  const _ManagerAvatar({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (ctx, snap) {
        String initial = 'M';
        Uint8List? photoBytes;
        String? photoUrl;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data()!;
          final fn = (d['firstName'] as String?)?.trim() ?? '';
          final un = (d['username'] as String?)?.trim() ?? '';
          final name = fn.isNotEmpty ? fn : (un.isNotEmpty ? un : '');
          if (name.isNotEmpty) initial = name[0].toUpperCase();
          photoUrl = (d['photoUrl'] as String?)?.trim() ??
              (d['photoURL'] as String?)?.trim();
          for (final k in [
            'photoBase64',
            'profilePhotoBase64',
            'imageBase64'
          ]) {
            final v = (d[k] as String?)?.trim();
            if (v != null && v.isNotEmpty) {
              try {
                photoBytes = base64Decode(v);
              } catch (_) {}
              break;
            }
          }
        }
        final safePhotoUrl = photoUrl ?? '';
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kAuthGold, width: 1.5),
            color: const Color(0xFF1A1A1A),
          ),
          clipBehavior: Clip.antiAlias,
          child: safePhotoUrl.isNotEmpty
              ? Image.network(
                  safePhotoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => photoBytes != null
                      ? Image.memory(photoBytes, fit: BoxFit.cover)
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
              : photoBytes != null
                  ? Image.memory(photoBytes, fit: BoxFit.cover)
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
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// _BellButton
// -----------------------------------------------------------------------------

class _BellButton extends StatelessWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: kAuthGold.withValues(alpha: 0.35)),
          ),
          child: Icon(
            LucideIcons.bell,
            color: Colors.white.withValues(alpha: 0.80),
            size: 20,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: _kOrangeDot,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// _SearchRow
// -----------------------------------------------------------------------------

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// -----------------------------------------------------------------------------
// _FilterChips
// -----------------------------------------------------------------------------

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('tous', LucideIcons.messageCircle, 'Tous'),
      ('intervenants', LucideIcons.user, 'Intervenants'),
      ('equipe', LucideIcons.users, 'Équipe'),
      ('systeme', LucideIcons.settings, 'Système'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips.map((c) {
          final isActive = selected == c.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => onSelect(c.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? kAuthGold : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? kAuthGold
                        : kAuthGold.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.$2,
                      size: 14,
                      color: isActive
                          ? Colors.black
                          : Colors.white.withValues(alpha: 0.70),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.$3,
                      style: GoogleFonts.inter(
                        color: isActive
                            ? Colors.black
                            : Colors.white.withValues(alpha: 0.70),
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _SectionHeader
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.unreadCount});
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Conversations',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Text(
              'Non lues ',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: unreadCount > 0 ? kAuthGold : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: GoogleFonts.inter(
                  color: unreadCount > 0
                      ? Colors.black
                      : Colors.white.withValues(alpha: 0.50),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// _ConvCard
// -----------------------------------------------------------------------------

class _ConvCard extends StatelessWidget {
  const _ConvCard({
    required this.conv,
    required this.timeLabel,
    required this.onTap,
    required this.onLongPress,
  });
  final _ConvItem conv;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kMsgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kMsgCardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConvAvatar(conv: conv),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.title.isEmpty ? 'Sans titre' : conv.title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conv.subtitle,
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conv.lastMessage.isEmpty
                        ? 'Aucun message'
                        : conv.lastMessage,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeLabel,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                if (conv.unread > 0)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: kAuthGold,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${conv.unread}',
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

// -----------------------------------------------------------------------------
// _ConvAvatar
// -----------------------------------------------------------------------------

class _ConvAvatar extends StatelessWidget {
  const _ConvAvatar({required this.conv});
  final _ConvItem conv;

  @override
  Widget build(BuildContext context) {
    Widget avatar;

    if (conv.type == 'intervenant') {
      if (conv.photoUrl != null && conv.photoUrl!.isNotEmpty) {
        avatar = ClipOval(
          child: Image.network(
            conv.photoUrl!,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              if (conv.photoBase64 != null && conv.photoBase64!.isNotEmpty) {
                try {
                  final bytes = base64Decode(conv.photoBase64!);
                  return Image.memory(
                    bytes,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  );
                } catch (_) {}
              }
              return _InitialAvatar(
                initial:
                    conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?',
              );
            },
          ),
        );
      } else if (conv.photoBase64 != null && conv.photoBase64!.isNotEmpty) {
        Uint8List? bytes;
        try {
          bytes = base64Decode(conv.photoBase64!);
        } catch (_) {}
        if (bytes != null) {
          avatar = ClipOval(
              child: Image.memory(bytes,
                  width: 60, height: 60, fit: BoxFit.cover));
        } else {
          avatar = _InitialAvatar(
              initial:
                  conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?');
        }
      } else {
        avatar = _InitialAvatar(
            initial: conv.title.isNotEmpty ? conv.title[0].toUpperCase() : '?');
      }
    } else {
      IconData icon;
      switch (conv.type) {
        case 'team':
          if (conv.photoUrl != null && conv.photoUrl!.isNotEmpty) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kAuthGold.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    conv.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _InitialAvatar(
                      initial: conv.title.isNotEmpty
                          ? conv.title[0].toUpperCase()
                          : '?',
                    ),
                  ),
                ),
              ],
            );
          }
          if (conv.memberPhotoBase64s.isNotEmpty) {
            avatar = _GroupAvatarStack(photos: conv.memberPhotoBase64s);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kAuthGold.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: avatar,
                ),
              ],
            );
          }
          icon = LucideIcons.users;
          break;
        case 'system':
          icon = LucideIcons.bell;
          break;
        case 'property':
          icon = LucideIcons.building;
          break;
        default:
          icon = LucideIcons.messageCircle;
      }
      avatar = Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kAuthGold.withValues(alpha: 0.12),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.40)),
        ),
        child: Icon(icon, color: kAuthGold, size: 24),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: kAuthGold.withValues(alpha: 0.45), width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: avatar,
        ),
        if (conv.type == 'intervenant' && conv.isAvailable)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _kGreenDot,
                shape: BoxShape.circle,
                border: Border.all(color: _kMsgBg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupAvatarStack extends StatelessWidget {
  const _GroupAvatarStack({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    final shown = photos.take(3).toList();
    return Container(
      color: const Color(0xFF101010),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i == 0
                  ? 0
                  : i == 1
                      ? 22
                      : 11,
              top: i == 2 ? 22 : 0,
              child: _GroupPhotoBubble(photo: shown[i]),
            ),
        ],
      ),
    );
  }
}

class _GroupPhotoBubble extends StatelessWidget {
  const _GroupPhotoBubble({required this.photo});

  final String photo;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(photo);
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF101010), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(bytes, fit: BoxFit.cover),
      );
    } catch (_) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kAuthGold.withValues(alpha: 0.16),
        ),
        child: const Icon(LucideIcons.user, color: kAuthGold, size: 16),
      );
    }
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.inter(
            color: kAuthGold,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _SkeletonList — loading placeholder
// -----------------------------------------------------------------------------

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kMsgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kMsgCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1E1E),
              border: Border.all(color: _kMsgCardBorder),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                    height: 14, width: 120, color: const Color(0xFF1E1E1E)),
                const SizedBox(height: 6),
                Container(
                    height: 11, width: 80, color: const Color(0xFF1A1A1A)),
                const SizedBox(height: 6),
                Container(
                    height: 11,
                    width: double.infinity,
                    color: const Color(0xFF1A1A1A)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _EmptyConvsState
// -----------------------------------------------------------------------------

class _EmptyConvsState extends StatelessWidget {
  const _EmptyConvsState({required this.onContactIntervenant});
  final VoidCallback onContactIntervenant;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAuthGold.withValues(alpha: 0.10),
                border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
              ),
              child: const Icon(LucideIcons.messageCircle,
                  color: kAuthGold, size: 30),
            ),
            const SizedBox(height: 20),
            Text(
              'Aucune conversation',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vos échanges avec les intervenants\napparaîtront ici.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onContactIntervenant,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kAuthGold.withValues(alpha: 0.70)),
                foregroundColor: kAuthGold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              ),
              child: Text(
                'Contacter un intervenant',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _ComposeFab
// -----------------------------------------------------------------------------

class _ComposeFab extends StatelessWidget {
  const _ComposeFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          color: kAuthGold,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x66D6A85A),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(LucideIcons.pencil, color: Colors.black, size: 22),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _ComposeSheet
// -----------------------------------------------------------------------------

class _ComposeSheet extends StatelessWidget {
  const _ComposeSheet({
    required this.onContactIntervenant,
    required this.onCreateGroup,
  });
  final VoidCallback onContactIntervenant;
  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Nouvelle conversation',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _ComposeOption(
              icon: LucideIcons.user,
              label: 'Contacter un intervenant',
              onTap: onContactIntervenant,
            ),
            const SizedBox(height: 10),
            _ComposeOption(
              icon: LucideIcons.users,
              label: 'Créer un groupe / équipe',
              onTap: onCreateGroup,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeOption extends StatelessWidget {
  const _ComposeOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAuthGold.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: kAuthGold, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.35),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// _MsgBottomNav
// -----------------------------------------------------------------------------

class _MsgBottomNav extends StatelessWidget {
  const _MsgBottomNav({
    required this.onAccueil,
    required this.onAgents,
    required this.onOffres,
    required this.onProfil,
  });

  final VoidCallback onAccueil;
  final VoidCallback onAgents;
  final VoidCallback onOffres;
  final VoidCallback onProfil;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        height: 64,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MsgNavItem(
              icon: LucideIcons.home,
              label: 'Accueil',
              isActive: false,
              onTap: onAccueil,
            ),
            _MsgNavItem(
              icon: LucideIcons.users,
              label: 'Agents',
              isActive: false,
              onTap: onAgents,
            ),
            _MsgNavItem(
              icon: LucideIcons.clipboardList,
              label: 'Offres',
              isActive: false,
              onTap: onOffres,
            ),
            const _MsgNavItem(
              icon: LucideIcons.messageCircle,
              label: 'Messages',
              isActive: true,
              hasDot: false,
            ),
            _MsgNavItem(
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

class _MsgNavItem extends StatelessWidget {
  const _MsgNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
    this.hasDot = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final bool hasDot;

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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isActive
                      ? kAuthGold
                      : Colors.white.withValues(alpha: 0.65),
                  size: isActive ? 22 : 20,
                ),
                if (hasDot)
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _kOrangeDot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
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

// _ConvActionSheet
class _ConvActionSheet extends StatelessWidget {
  const _ConvActionSheet(
      {required this.conv, required this.onBlock, required this.onDelete});
  final _ConvItem conv;
  final VoidCallback onBlock;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 16),
            Text(conv.title.isEmpty ? 'Conversation' : conv.title,
                style: GoogleFonts.cormorantGaramond(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            _ActionTile(
                icon: LucideIcons.ban,
                label: 'Bloquer cet utilisateur',
                color: const Color(0xFFF59E0B),
                onTap: onBlock),
            const SizedBox(height: 10),
            _ActionTile(
                icon: LucideIcons.trash2,
                label: 'Supprimer definititivement',
                color: const Color(0xFFEF4444),
                onTap: onDelete),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler',
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.inter(
                  color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// _CreateGroupSheet
class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.managerUid});
  final String managerUid;
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final Set<String> _selectedIds = {};
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;
  bool _saving = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    try {
      final conversations = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: widget.managerUid)
          .get();
      final ids = <String>{};
      for (final doc in conversations.docs) {
        final participants = ((doc.data()['participants'] as List?) ?? const [])
            .map((e) => '$e')
            .where((e) => e != widget.managerUid)
            .toList();
        ids.addAll(participants);
      }

      final list = <Map<String, dynamic>>[];
      for (final id in ids) {
        final d = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(id)
            .get();
        final data = d.data() ?? const <String, dynamic>{};
        String name = '';
        for (final k in ['username', 'fullName', 'displayName', 'firstName']) {
          final v = (data[k] as String?)?.trim();
          if (v != null && v.isNotEmpty) {
            name = v;
            break;
          }
        }
        if (name.isEmpty) continue;
        final subtitle = _resolveWorkerSubtitle(
              department: (data['department'] as String?)?.trim(),
              specialty: _resolveSpecialtyValue(data),
              fallbackRole: (data['role'] as String?)?.trim(),
            ) ??
            '';
        String? photo;
        for (final k in ['photoBase64', 'profilePhotoBase64', 'imageBase64']) {
          final v = (data[k] as String?)?.trim();
          if (v != null && v.isNotEmpty) {
            photo = v;
            break;
          }
        }
        list.add(<String, dynamic>{
          'id': id,
          'name': name,
          'subtitle': subtitle,
          'photo': photo,
        });
      }
      if (mounted) {
        setState(() {
          _workers = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.trim().isEmpty) return _workers;
    final q = _searchQuery.toLowerCase();
    return _workers
        .where((w) =>
            (w['name'] as String).toLowerCase().contains(q) ||
            (w['subtitle'] as String).toLowerCase().contains(q))
        .toList();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final participants = [widget.managerUid, ..._selectedIds];
      final memberPhotos = _workers
          .where((w) => _selectedIds.contains(w['id']))
          .map((w) => (w['photo'] as String?)?.trim() ?? '')
          .where((e) => e.isNotEmpty)
          .take(3)
          .toList();
      await FirebaseFirestore.instance.collection('conversations').add({
        'type': 'team',
        'title': name,
        'participants': participants,
        'memberCount': participants.length,
        'memberPhotoBase64s': memberPhotos,
        'lastMessage': 'Groupe cree',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadBy': <String, int>{},
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.managerUid,
        'isActive': true,
        'blockedBy': <String>[],
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _nameCtrl.text.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.80),
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 18),
              Text('Creer un groupe',
                  style: GoogleFonts.cormorantGaramond(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
                ),
                child: TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  cursorColor: kAuthGold,
                  decoration: InputDecoration(
                    hintText: 'Nom du groupe...',
                    hintStyle: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 14),
                    prefixIcon: const Icon(LucideIcons.users,
                        color: kAuthGold, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  cursorColor: kAuthGold,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un intervenant...',
                    hintStyle: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.30),
                        fontSize: 13),
                    prefixIcon: Icon(LucideIcons.search,
                        color: Colors.white.withValues(alpha: 0.35), size: 16),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kAuthGold))
                    : _filtered.isEmpty
                        ? Center(
                            child: Text('Aucun intervenant disponible.',
                                style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.40),
                                    fontSize: 13)))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final w = _filtered[i];
                              final id = w['id'] as String;
                              final selected = _selectedIds.contains(id);
                              return GestureDetector(
                                onTap: () => setState(() => selected
                                    ? _selectedIds.remove(id)
                                    : _selectedIds.add(id)),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? kAuthGold.withValues(alpha: 0.12)
                                        : const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: selected
                                            ? kAuthGold.withValues(alpha: 0.50)
                                            : Colors.white
                                                .withValues(alpha: 0.08)),
                                  ),
                                  child: Row(children: [
                                    _WorkerThumb(
                                        photo: w['photo'] as String?,
                                        name: w['name'] as String),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(w['name'] as String,
                                            style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                        if ((w['subtitle'] as String).isNotEmpty)
                                          Text(w['subtitle'] as String,
                                              style: GoogleFonts.inter(
                                                  color: kAuthGold,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500)),
                                      ],
                                    )),
                                    Icon(
                                        selected
                                            ? LucideIcons.checkCircle
                                            : LucideIcons.circle,
                                        color: selected
                                            ? kAuthGold
                                            : Colors.white
                                                .withValues(alpha: 0.25),
                                        size: 20),
                                  ]),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (canCreate && !_saving) ? _create : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAuthGold,
                    disabledBackgroundColor: kAuthGold.withValues(alpha: 0.30),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : Text(
                          _selectedIds.isEmpty
                              ? 'Creer le groupe'
                              : 'Creer avec ${_selectedIds.length} membre(s)',
                          style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: FontWeight.w700),
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

class _WorkerThumb extends StatelessWidget {
  const _WorkerThumb({required this.photo, required this.name});
  final String? photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      try {
        final bytes = base64Decode(photo!);
        return ClipOval(
            child:
                Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover));
      } catch (_) {}
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kAuthGold.withValues(alpha: 0.15),
        border: Border.all(color: kAuthGold.withValues(alpha: 0.40)),
      ),
      child: Center(
          child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
            color: kAuthGold, fontSize: 14, fontWeight: FontWeight.w700),
      )),
    );
  }
}
