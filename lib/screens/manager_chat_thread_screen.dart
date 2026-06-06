import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_os/screens/auth_screen.dart';
import 'package:hotel_lux_os/services/manager_unread_service.dart';
import 'package:hotel_lux_os/services/app_session_service.dart';
import 'package:hotel_lux_os/services/app_env.dart';
import 'package:hotel_lux_os/services/vps_media_service.dart';
import 'package:http/http.dart' as http;
import 'package:hotel_lux_os/widgets/google_address_picker_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

const _kThreadBg = Color(0xFF070707);
const _kThreadCard = Color(0xFF111111);
const _kThreadBorder = Color(0x33D6A85A);
const _kThreadSurface = Color(0xCC161616);
const _kThreadPeerBubble = Color(0xFF212121);
const _kChatBackgroundAsset = 'assets/stayfix_chat_background_dark_doodle.webp';
const _kSeenBlue = Color(0xFF2196F3);
const _kThreadHeaderHeight = 122.0;

const Map<String, IconData> _kReactionIcons = {
  'thumbs_up': LucideIcons.thumbsUp,
  'heart': LucideIcons.heart,
  'check': LucideIcons.check,
  'clap': LucideIcons.partyPopper,
  'fire': LucideIcons.flame,
  'pin': LucideIcons.pin,
};

const Map<String, Color> _kReactionColors = {
  'thumbs_up': Color(0xFF4F8CFF),
  'heart': Color(0xFFD6A85A),
  'check': Color(0xFF4DD4D2),
  'clap': Color(0xFF8B96A9),
  'fire': Color(0xFFFF9A54),
  'pin': Color(0xFFAAB3C2),
};

class _MessageSenderSummary {
  const _MessageSenderSummary({
    required this.name,
    this.avatarBase64,
    this.avatarUrl,
    this.roleBadge,
    this.apartmentBadge,
  });

  final String name;
  final String? avatarBase64;
  final String? avatarUrl;
  final String? roleBadge;
  final String? apartmentBadge;
}

class _MissionAssigneeOption {
  const _MissionAssigneeOption({
    required this.id,
    required this.name,
    required this.roleLabel,
    this.apartmentBadge,
  });

  final String id;
  final String name;
  final String roleLabel;
  final String? apartmentBadge;
}

class _SystemBannerPalette {
  const _SystemBannerPalette({
    required this.fill,
    required this.border,
    required this.foreground,
  });

  final Color fill;
  final Color border;
  final Color foreground;
}

bool _isWorkerAccountType(String value) {
  final accountType = value.trim().toLowerCase();
  return accountType == 'concierge' ||
      accountType == 'stayfix_job' ||
      accountType == 'worker';
}

List<String> _readStringList(dynamic raw) {
  return ((raw as List?) ?? const <dynamic>[])
      .map((entry) => '$entry'.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

String _resolveRoleBadge(String accountType, Map<String, dynamic> userData) {
  if (accountType == 'concierge' || accountType == 'stayfix_job') {
    return 'Concierge StayFix';
  }
  if (accountType == 'manager' || accountType == 'apartment_manager') {
    return 'Gestionnaire';
  }
  if (accountType == 'worker') {
    return 'Intervenant';
  }
  final role = (userData['role'] as String?)?.trim() ?? '';
  return role.isNotEmpty ? role : 'Membre';
}

_SystemBannerPalette _resolveSystemBannerPalette(String kind) {
  switch (kind.trim()) {
    case 'member_added':
      return const _SystemBannerPalette(
        fill: Color(0x9922C55E),
        border: Color(0xAA86EFAC),
        foreground: Colors.white,
      );
    case 'member_removed':
      return const _SystemBannerPalette(
        fill: Color(0x99EF4444),
        border: Color(0xAAFCA5A5),
        foreground: Colors.white,
      );
    case 'mission_completed':
      return const _SystemBannerPalette(
        fill: Color(0x9922C55E),
        border: Color(0xAA86EFAC),
        foreground: Colors.white,
      );
    default:
      return const _SystemBannerPalette(
        fill: Color(0x7A0F172A),
        border: Color(0x55FFFFFF),
        foreground: Colors.white,
      );
  }
}

String _resolveCurrentActorName() {
  final userData = AppSessionService.currentUserData;
  final firstName = (userData['firstName'] as String?)?.trim() ?? '';
  final lastName = (userData['lastName'] as String?)?.trim() ?? '';
  final fullName = '$firstName $lastName'.trim();
  if (fullName.isNotEmpty) return fullName;
  final username = (userData['username'] as String?)?.trim();
  if (username != null && username.isNotEmpty) return username;
  final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return 'Gestionnaire';
}

Future<void> _clearConversationHistoryById(String conversationId) async {
  final messagesRef = FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId)
      .collection('messages');
  final messagesSnapshot = await messagesRef.get();
  final allFileIds = <String>[];
  final batch = FirebaseFirestore.instance.batch();
  for (final doc in messagesSnapshot.docs) {
    final fileIds = ((doc.data()['fileIds'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    allFileIds.addAll(fileIds);
    batch.delete(doc.reference);
  }
  await batch.commit();
  if (allFileIds.isNotEmpty) {
    await VpsMediaService.deleteFiles(allFileIds);
  }
  await FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId)
      .set({
    'lastMessage': '',
    'systemBannerText': 'History was cleared',
    'systemBannerKind': 'system',
    'systemBannerAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

class ManagerChatThreadScreen extends StatefulWidget {
  const ManagerChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
    required this.isAvailable,
    this.initialBannerText,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;
  final bool isAvailable;
  final String? initialBannerText;

  @override
  State<ManagerChatThreadScreen> createState() =>
      _ManagerChatThreadScreenState();
}

class _ManagerChatThreadScreenState extends State<ManagerChatThreadScreen> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  // Cached streams — must not be recreated on setState or the StreamBuilders
  // cancel their subscriptions and briefly show an empty state.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _conversationStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  bool _isSending = false;
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  String? _recordingPath;
  Timer? _recordingTicker;
  Duration _recordingElapsed = Duration.zero;
  bool _isMarkingSeen = false;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<int> _recordingWaveform = [];
  Timer? _typingTimer;
  bool _showRecordComposer = false;
  bool _isRecordLocked = false;
  bool _isRecordPaused = false;
  double _holdDx = 0;
  double _holdDy = 0;
  bool _recordCanceledByGesture = false;
  String? _lastIncomingMessageId;
  String? _ephemeralBannerText;
  String? _sendingLabel;
  Timer? _ephemeralBannerTimer;
  final Set<String> _seenMessageIds = <String>{};
  List<String> _participantIds = const <String>[];
  final Map<String, _MessageSenderSummary> _senderCache =
      <String, _MessageSenderSummary>{};

  bool _missionsMinimized = false;
  int _activeMissionsCount = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _missionsCountSub;

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _typingTimer?.cancel();
    _amplitudeSub?.cancel();
    _ephemeralBannerTimer?.cancel();
    _missionsCountSub?.cancel();
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _conversationStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots();
    _messagesStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(50)
        .snapshots();
    _missionsCountSub = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('tasks')
        .snapshots()
        .listen((snap) {
      final count = snap.docs.where((d) {
        final status = (d.data()['status'] as String?)?.trim() ?? 'open';
        return status != 'completed' && status != 'deleted';
      }).length;
      if (mounted) setState(() => _activeMissionsCount = count);
    });
    if (widget.initialBannerText?.trim().isNotEmpty == true) {
      _showEphemeralBanner(widget.initialBannerText!.trim());
    }
    unawaited(
        ManagerUnreadService.markConversationAsRead(widget.conversationId));
  }

  DocumentReference<Map<String, dynamic>> get _conversationRef =>
      FirebaseFirestore.instance.collection('conversations').doc(
            widget.conversationId,
          );

  void _showEphemeralBanner(String text) {
    _ephemeralBannerTimer?.cancel();
    setState(() => _ephemeralBannerText = text);
    _ephemeralBannerTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _ephemeralBannerText = null);
    });
  }

  Future<_MessageSenderSummary?> _loadSenderSummary(String senderId) async {
    if (senderId.trim().isEmpty) return null;
    final cached = _senderCache[senderId];
    if (cached != null) return cached;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(senderId)
        .get();
    final profileDoc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(senderId)
        .get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final profileData = profileDoc.data() ?? const <String, dynamic>{};
    final firstName = (userData['firstName'] as String?)?.trim() ?? '';
    final lastName = (userData['lastName'] as String?)?.trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final fallback = (profileData['username'] as String?)?.trim() ??
        (userData['username'] as String?)?.trim() ??
        'Membre';
    final accountType =
        (userData['accountType'] as String?)?.trim().toLowerCase() ?? '';
    final apartmentId = ((userData['apartmentId'] ??
                userData['propertyId'] ??
                userData['managedPropertyId']) as String?)
            ?.trim() ??
        '';
    String? apartmentBadge;
    if (apartmentId.isNotEmpty) {
      final apartmentDoc = await FirebaseFirestore.instance
          .collection('hotels')
          .doc(apartmentId)
          .get();
      apartmentBadge = (apartmentDoc.data()?['name'] as String?)?.trim();
    }
    final summary = _MessageSenderSummary(
      name: fullName.isNotEmpty ? fullName : fallback,
      avatarUrl: VpsMediaService.resolveProfileImageUrl(profileData),
      avatarBase64: (profileData['photoBase64'] as String?)?.trim() ??
          (profileData['profilePhotoBase64'] as String?)?.trim() ??
          (profileData['imageBase64'] as String?)?.trim(),
      roleBadge: _resolveRoleBadge(accountType, userData),
      apartmentBadge: apartmentBadge != null && apartmentBadge.isNotEmpty
          ? apartmentBadge
          : null,
    );
    _senderCache[senderId] = summary;
    return summary;
  }

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _conversationRef.collection('messages');

  CollectionReference<Map<String, dynamic>> get _tasksRef =>
      _conversationRef.collection('tasks');

  Future<void> _markIncomingMessagesSeen(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) async {
    if (_isMarkingSeen) return;

    final pending = docs.where((doc) {
      if (_seenMessageIds.contains(doc.id)) return false;
      final data = doc.data();
      if (data['senderId'] == uid) return false;
      final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const [];
      return !seenBy.contains(uid);
    }).toList();

    if (pending.isEmpty) return;

    _isMarkingSeen = true;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pending) {
        batch.set(
            doc.reference,
            {
              'deliveredTo': FieldValue.arrayUnion([uid]),
              'seenBy': FieldValue.arrayUnion([uid]),
              'seenAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      _seenMessageIds.addAll(pending.map((doc) => doc.id));
      await ManagerUnreadService.markConversationAsRead(widget.conversationId);
    } catch (_) {
    } finally {
      _isMarkingSeen = false;
    }
  }

  Future<void> _deleteMessage(
    String messageId, {
    required List<String> fileIds,
  }) async {
    try {
      await _messagesRef.doc(messageId).delete();
      if (fileIds.isNotEmpty) {
        await VpsMediaService.deleteFiles(fileIds);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de supprimer ce message pour le moment.');
    }
  }

  Future<void> _setTyping(bool isTyping) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    try {
      await _conversationRef.set({
        'typingBy': {uid: isTyping},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _handleComposerChanged() {
    setState(() {});
    final hasText = _controller.text.trim().isNotEmpty;
    unawaited(_setTyping(hasText));
    _typingTimer?.cancel();
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        unawaited(_setTyping(false));
      });
    }
  }

  Future<void> _openChatInfoScreen(Map<String, dynamic> data) async {
    final title = (data['title'] as String?)?.trim();
    final subtitle = (data['type'] as String?)?.trim() == 'team'
        ? _buildGroupSubtitle(data)
        : widget.subtitle;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ChatContactInfoScreen(
          conversationId: widget.conversationId,
          title: title?.isNotEmpty == true ? title! : widget.title,
          subtitle: subtitle,
          avatarBase64: widget.avatarBase64,
          avatarUrl:
              VpsMediaService.resolveProfileImageUrl(data) ?? widget.avatarUrl,
        ),
      ),
    );
  }

  Future<void> _showChatOptionsSheet() async {
    final snapshot = await _conversationRef.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final conversationType = (data['type'] as String?)?.trim() ?? 'intervenant';
    final participants = ((data['participants'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final mutedBy = ((data['mutedBy'] as List?) ?? const []).map((e) => '$e');
    final uid = _currentUid;
    bool notificationsMuted = mutedBy.contains(uid);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ChatOptionTile(
                      icon: LucideIcons.bell,
                      title: 'Notifications',
                      trailing: Switch(
                        value: !notificationsMuted,
                        activeTrackColor: const Color(0xFF22C55E),
                        activeThumbColor: Colors.white,
                        onChanged: (enabled) async {
                          notificationsMuted = !enabled;
                          setModalState(() {});
                          final op = notificationsMuted
                              ? FieldValue.arrayUnion([uid])
                              : FieldValue.arrayRemove([uid]);
                          await _conversationRef.set({
                            'mutedBy': op,
                          }, SetOptions(merge: true));
                        },
                      ),
                    ),
                    if (conversationType == 'team')
                      _ChatOptionTile(
                        icon: LucideIcons.pin,
                        title: 'Ajouter une mission',
                        onTap: () async {
                          Navigator.pop(context);
                          await _openCreateTaskSheet();
                        },
                      ),
                    if (conversationType == 'team')
                      _ChatOptionTile(
                        icon: LucideIcons.userPlus,
                        title: 'Add members',
                        onTap: () async {
                          Navigator.pop(context);
                          await showModalBottomSheet<void>(
                            context: this.context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => _AddGroupMembersSheet(
                              conversationId: widget.conversationId,
                              managerUid: uid,
                              existingParticipantIds: participants.toSet(),
                            ),
                          );
                        },
                      ),
                    _ChatOptionTile(
                      icon: LucideIcons.clipboardList,
                      title: 'Missions',
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.of(this.context).push(
                          MaterialPageRoute(
                            builder: (_) => _MissionHistoryScreen(
                              conversationId: widget.conversationId,
                            ),
                          ),
                        );
                      },
                    ),
                    _ChatOptionTile(
                      icon: LucideIcons.info,
                      title: conversationType == 'team'
                          ? 'Group info'
                          : 'Contact info',
                      onTap: () async {
                        Navigator.pop(context);
                        await _openChatInfoScreen(data);
                      },
                    ),
                    _ChatOptionTile(
                      icon: LucideIcons.flag,
                      title: 'Report abuse',
                      onTap: () async {
                        Navigator.pop(context);
                        await _reportConversationAbuse(data);
                      },
                    ),
                    _ChatOptionTile(
                      icon: LucideIcons.trash2,
                      title: 'Clear chat',
                      destructive: true,
                      onTap: () async {
                        Navigator.pop(context);
                        await _clearChatHistory();
                      },
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

  Future<void> _clearChatHistory() async {
    try {
      await _clearConversationHistoryById(widget.conversationId);
      _showEphemeralBanner('History was cleared');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de vider cette conversation pour le moment.');
    }
  }

  Future<void> _reportConversationAbuse(
    Map<String, dynamic> conversationData,
  ) async {
    final uid = _currentUid;
    if (uid.isEmpty) {
      _showSnack('Impossible de signaler cette conversation pour le moment.');
      return;
    }

    final detailsController = TextEditingController();
    String selectedReason = 'harassment';
    final reasons = <Map<String, String>>[
      {'id': 'harassment', 'label': 'Harcelement ou intimidation'},
      {'id': 'hate', 'label': 'Contenu haineux ou offensant'},
      {'id': 'spam', 'label': 'Spam ou sollicitations abusives'},
      {'id': 'impersonation', 'label': 'Usurpation d identite'},
      {'id': 'other', 'label': 'Autre probleme'},
    ];

    final confirmed = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (sheetContext) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 14,
                      right: 14,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 14,
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      decoration: BoxDecoration(
                        color: _kThreadCard,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _kThreadBorder),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(
                            'Signaler un abus',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Le signalement est envoye a l equipe StayFix sans modifier automatiquement la conversation.',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.72),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...reasons.map((reason) {
                            final isSelected = selectedReason == reason['id'];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                isSelected
                                    ? LucideIcons.checkCircle2
                                    : LucideIcons.circle,
                                color: isSelected
                                    ? kAuthGold
                                    : Colors.white.withValues(alpha: 0.45),
                                size: 18,
                              ),
                              title: Text(
                                reason['label']!,
                                style: GoogleFonts.inter(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.84),
                                ),
                              ),
                              onTap: () =>
                                  setModalState(() => selectedReason = reason['id']!),
                            );
                          }),
                          const SizedBox(height: 8),
                          TextField(
                            controller: detailsController,
                            minLines: 3,
                            maxLines: 5,
                            style: GoogleFonts.inter(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Ajoutez un contexte utile (optionnel)',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.white54,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide:
                                    const BorderSide(color: _kThreadBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide:
                                    const BorderSide(color: _kThreadBorder),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext, false),
                                  style: OutlinedButton.styleFrom(
                                    side:
                                        const BorderSide(color: _kThreadBorder),
                                    foregroundColor: Colors.white70,
                                  ),
                                  child: const Text('Annuler'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAuthGold,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Envoyer'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ) ??
        false;

    final details = detailsController.text.trim();
    detailsController.dispose();
    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance.collection('abuse_reports').add({
        'type': 'chat_conversation',
        'conversationId': widget.conversationId,
        'conversationTitle': widget.title,
        'conversationSubtitle': widget.subtitle,
        'conversationType': (conversationData['type'] as String?)?.trim() ?? '',
        'participantIds': ((conversationData['participants'] as List?) ?? const [])
            .map((entry) => '$entry')
            .where((entry) => entry.trim().isNotEmpty)
            .toList(),
        'reportedByUserId': uid,
        'reportedByAccountType':
            (AppSessionService.currentUserData['accountType'] as String?)
                    ?.trim() ??
                '',
        'reason': selectedReason,
        'details': details,
        'status': 'open',
        'lastMessagePreview':
            (conversationData['lastMessage'] as String?)?.trim() ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showSnack('Signalement envoye. Merci.');
    } catch (_) {
      _showSnack('Impossible d envoyer le signalement pour le moment.');
    }
  }

  Future<void> _reactToMessage(String messageId, String reaction) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    try {
      await _messagesRef.doc(messageId).set({
        'reaction': reaction,
        'reactionByUserId': uid,
        'reactionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      SystemSound.play(SystemSoundType.click);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d ajouter cette reaction pour le moment.');
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    _controller.clear();
    setState(() {});
    unawaited(_setTyping(false));
    await _sendMessage(text: text, lastMessage: text);
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isSending) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (picked == null) return;

      if (mounted) {
        setState(() => _sendingLabel = 'Envoi de la photo...');
      }
      final uploaded = await VpsMediaService.uploadFile(
        file: File(picked.path),
        category: 'chat-image',
        conversationId: widget.conversationId,
      );

      await _sendMessage(
        imageUrl: uploaded.url,
        imageMimeType: uploaded.mimeType,
        imageFileId: uploaded.fileId,
        imageName: picked.name,
        imageSizeBytes: uploaded.sizeBytes,
        imageWidth: uploaded.width,
        imageHeight: uploaded.height,
        lastMessage: 'Photo',
      );
    } catch (_) {
      _showSnack('Impossible d envoyer cette photo pour le moment.');
    } finally {
      if (mounted) {
        setState(() => _sendingLabel = null);
      }
    }
  }

  Future<void> _openAttachmentPicker() async {
    if (_isSending) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: _kThreadCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _kThreadBorder),
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
                _AttachmentOption(
                  icon: LucideIcons.image,
                  title: 'Photo galerie',
                  subtitle: 'Envoyer une photo depuis la galerie',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
                _AttachmentOption(
                  icon: LucideIcons.mapPin,
                  title: 'Partager une adresse',
                  subtitle: 'Choisir une adresse via Google Maps',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openAddressPickerSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddressPickerSheet() async {
    final mapsKey = await AppEnv.get(
      'GOOGLE_MAPS_API_KEY',
      fallback: '',
    );
    if (!mounted) return;

    final result = await showModalBottomSheet<GoogleAddressSelection>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: GoogleAddressPickerScreen(
              title: 'Modifier adresse',
              apiKey: mapsKey,
              isModal: true,
              returnSelectionObject: true,
            ),
          ),
        );
      },
    );

    if (result == null || result.address.trim().isEmpty) return;
    await _sendMessage(
      address: result.address.trim(),
      latitude: result.latitude,
      longitude: result.longitude,
      lastMessage: 'Adresse partagee',
    );
  }

  Future<void> _toggleRecording() async {
    if (_isSending) return;
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      await _startRecording(
        locked: true,
        fromHold: false,
      );
    }
  }

  Future<void> _startRecording({
    required bool locked,
    required bool fromHold,
  }) async {
    try {
      if (!await _recorder.hasPermission()) {
        _showSnack('Microphone non autorise.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordingWaveform
        ..clear()
        ..addAll(List<int>.filled(36, 4));
      _amplitudeSub?.cancel();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen((amp) {
        if (!mounted || !_isRecording) return;
        final db = amp.current;
        final normalized = (((db + 45).clamp(0, 45) / 45) * 30).round() + 6;
        setState(() {
          if (_recordingWaveform.length > 52) {
            _recordingWaveform.removeAt(0);
          }
          _recordingWaveform.add(normalized);
        });
      });

      SystemSound.play(SystemSoundType.click);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _isRecordLocked = locked;
        _showRecordComposer = true;
        _isRecordPaused = false;
        _recordCanceledByGesture = false;
        _holdDx = 0;
        _holdDy = 0;
        _recordingStartedAt = DateTime.now();
        _recordingPath = path;
        _recordingElapsed = Duration.zero;
      });
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || _recordingStartedAt == null || _isRecordPaused) return;
        setState(() {
          _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
        });
      });
    } catch (_) {
      _showSnack('Impossible de demarrer l enregistrement.');
    }
  }

  Future<void> _pauseResumeRecording() async {
    if (!_isRecording) return;
    try {
      if (_isRecordPaused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
      if (!mounted) return;
      setState(() {
        _isRecordPaused = !_isRecordPaused;
      });
    } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTicker?.cancel();
      _amplitudeSub?.cancel();
      await _recorder.stop();
    } catch (_) {}
    final path = _recordingPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _showRecordComposer = false;
      _isRecordLocked = false;
      _isRecordPaused = false;
      _recordingStartedAt = null;
      _recordingPath = null;
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
      _holdDx = 0;
      _holdDy = 0;
    });
  }

  Future<void> _stopAndSendRecording() async {
    String? resolvedPath;
    try {
      final path = await _recorder.stop();
      resolvedPath = path ?? _recordingPath;
      final waveformSnapshot = _recordingWaveform.isEmpty
          ? const <int>[]
          : List<int>.from(_recordingWaveform);
      _recordingTicker?.cancel();
      _amplitudeSub?.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _showRecordComposer = false;
        _isRecordLocked = false;
        _isRecordPaused = false;
        _recordingElapsed = Duration.zero;
      });

      if (resolvedPath == null || resolvedPath.isEmpty) return;

      final durationMs = _recordingStartedAt == null
          ? null
          : DateTime.now().difference(_recordingStartedAt!).inMilliseconds;
      _recordingStartedAt = null;
      _recordingPath = null;
      _holdDx = 0;
      _holdDy = 0;
      if (mounted) {
        setState(() => _sendingLabel = 'Envoi du message vocal...');
      }

      final uploaded = await VpsMediaService.uploadFile(
        file: File(resolvedPath),
        category: 'chat-audio',
        conversationId: widget.conversationId,
        durationMs: durationMs,
      );

      await _sendMessage(
        audioUrl: uploaded.url,
        audioMimeType: uploaded.mimeType,
        audioFileId: uploaded.fileId,
        audioDurationMs: uploaded.durationMs ?? durationMs,
        audioSizeBytes: uploaded.sizeBytes,
        audioWaveform: waveformSnapshot,
        lastMessage: 'Message vocal',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _showRecordComposer = false;
        _isRecordLocked = false;
        _isRecordPaused = false;
        _recordingStartedAt = null;
        _recordingPath = null;
        _recordingElapsed = Duration.zero;
        _recordingWaveform.clear();
        _holdDx = 0;
        _holdDy = 0;
      });
      _showSnack('Impossible d envoyer le vocal pour le moment.');
    } finally {
      if (mounted) {
        setState(() => _sendingLabel = null);
      }
      if (resolvedPath != null && resolvedPath.isNotEmpty) {
        try {
          await File(resolvedPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _sendMessage({
    String? text,
    String? imageUrl,
    String? imageMimeType,
    String? imageFileId,
    String? imageName,
    int? imageSizeBytes,
    int? imageWidth,
    int? imageHeight,
    String? audioUrl,
    String? audioMimeType,
    String? audioFileId,
    int? audioDurationMs,
    int? audioSizeBytes,
    List<int>? audioWaveform,
    String? address,
    double? latitude,
    double? longitude,
    required String lastMessage,
  }) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;

    final fileIds = <String>[
      if (imageFileId != null && imageFileId.isNotEmpty) imageFileId,
      if (audioFileId != null && audioFileId.isNotEmpty) audioFileId,
    ];

    setState(() => _isSending = true);
    try {
      final messageRef = _messagesRef.doc();
      final messageData = <String, dynamic>{
        'senderId': uid,
        'type': audioUrl != null
            ? 'audio'
            : imageUrl != null
                ? 'image'
                : address != null
                    ? 'address'
                    : 'text',
        'text': text ?? '',
        'imageUrl': imageUrl,
        'imageMimeType': imageMimeType,
        'imageFileId': imageFileId,
        'imageName': imageName,
        'imageSizeBytes': imageSizeBytes,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'audioUrl': audioUrl,
        'audioMimeType': audioMimeType,
        'audioFileId': audioFileId,
        'audioDurationMs': audioDurationMs,
        'audioSizeBytes': audioSizeBytes,
        'audioWaveform': audioWaveform,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'fileIds': fileIds,
        'mediaStorage': fileIds.isEmpty ? null : 'vps',
        'sentAt': FieldValue.serverTimestamp(),
        'deliveredTo': [uid],
        'seenBy': [uid],
        'createdAt': FieldValue.serverTimestamp(),
      };
      await messageRef.set(messageData);
      SystemSound.play(SystemSoundType.click);
      unawaited(_updateConversationPreview(lastMessage));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendingLabel = null;
        });
      }
    }
  }

  Future<void> _updateConversationPreview(String lastMessage) async {
    try {
      final uid = _currentUid;
      if (uid.isEmpty) return;
      final payload = <String, dynamic>{
        'lastMessage': lastMessage,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': uid,
        'lastReadAt.$uid': FieldValue.serverTimestamp(),
        'unreadBy.$uid': 0,
      };
      for (final participantId in _participantIds) {
        if (participantId == uid) continue;
        payload['unreadBy.$participantId'] = FieldValue.increment(1);
      }
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .set(payload, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _appendSystemMessage(String text) async {
    final uid = _currentUid;
    if (uid.isEmpty || text.trim().isEmpty) return;
    await _messagesRef.add({
      'senderId': uid,
      'text': text.trim(),
      'messageType': 'system',
      'deliveredTo': [uid],
      'seenBy': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _openCreateTaskSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CreateMissionSheet(
        conversationId: widget.conversationId,
        managerUid: _currentUid,
        onCreate: _createMission,
      ),
    );
  }

  Future<void> _createMission({
    required String title,
    required String description,
    required List<String> assignedMemberIds,
    required List<String> assignedMemberNames,
  }) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    final cleanedIds = assignedMemberIds
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    final cleanedNames = assignedMemberNames
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    await _tasksRef.add({
      'title': title.trim(),
      'description': description.trim(),
      'assignedMemberIds': cleanedIds,
      'assignedMemberNames': cleanedNames,
      'assignedToId': cleanedIds.length == 1 ? cleanedIds.first : null,
      'assignedToName': cleanedNames.length == 1 ? cleanedNames.first : null,
      'status': 'open',
      'createdBy': uid,
      'createdByName': AppSessionService.currentUserData['username'] ??
          FirebaseAuth.instance.currentUser?.displayName,
      'completedByIds': const <String>[],
      'completedByNames': const <String>[],
      'completedCount': 0,
      'targetCount': cleanedIds.isEmpty ? 0 : cleanedIds.length,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final preview = 'Nouvelle mission: ${title.trim()}';
    await _appendSystemMessage(preview);
    await _updateConversationPreview(preview);
    await _conversationRef.set({
      'activeTaskCount': FieldValue.increment(1),
      'conversationTag': 'missions',
      'systemBannerText': 'Nouvelle mission epinglee.',
      'systemBannerKind': 'mission_created',
      'systemBannerAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _completeMission(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    final title = (data['title'] as String?)?.trim() ?? 'Mission';
    final completedByIds = _readStringList(data['completedByIds']);
    if (completedByIds.contains(uid)) return;
    final assigneeIds = _readStringList(data['assignedMemberIds']);
    final totalTarget = assigneeIds.isEmpty
        ? (((data['targetCount'] as num?)?.toInt() ?? 0) > 0
            ? (data['targetCount'] as num).toInt()
            : 1)
        : assigneeIds.length;
    final actorName = _resolveCurrentActorName();
    final nextCompletedIds = <String>{...completedByIds, uid}.toList();
    final completedByNames = _readStringList(data['completedByNames']);
    final nextCompletedNames =
        <String>{...completedByNames, actorName}.toList();
    final nextCount = nextCompletedIds.length;
    final isFullyCompleted = nextCount >= totalTarget;
    await _tasksRef.doc(taskId).set({
      'status': isFullyCompleted ? 'completed' : 'open',
      'completedByIds': nextCompletedIds,
      'completedByNames': nextCompletedNames,
      'completedCount': nextCount,
      'targetCount': totalTarget,
      'completedBy': isFullyCompleted ? uid : null,
      'completedAt': isFullyCompleted ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final preview = isFullyCompleted
        ? 'Mission terminee: $title'
        : 'Mission en cours: $title ($nextCount/$totalTarget)';
    await _appendSystemMessage(preview);
    await _updateConversationPreview(preview);
    await _conversationRef.set({
      if (isFullyCompleted) 'activeTaskCount': FieldValue.increment(-1),
      'systemBannerText': isFullyCompleted
          ? 'Mission terminee.'
          : 'Progression mission: $nextCount/$totalTarget',
      'systemBannerKind':
          isFullyCompleted ? 'mission_completed' : 'mission_progress',
      'systemBannerAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _removeMission(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    final title = (data['title'] as String?)?.trim() ?? 'Mission';
    await _tasksRef.doc(taskId).set({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _appendSystemMessage('Mission supprimee: $title');
    await _updateConversationPreview('Mission supprimee: $title');
    await _conversationRef.set({
      'activeTaskCount': FieldValue.increment(-1),
      'systemBannerText': 'Une mission a ete supprimee.',
      'systemBannerKind': 'mission_deleted',
      'systemBannerAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _acceptMission(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    final title = (data['title'] as String?)?.trim() ?? 'Mission';
    await _tasksRef.doc(taskId).set({
      'status': 'accepted',
      'acceptedBy': uid,
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _appendSystemMessage('Mission acceptee: $title');
    await _updateConversationPreview('Mission acceptee: $title');
    await _conversationRef.set({
      'systemBannerText': 'Mission acceptee.',
      'systemBannerKind': 'mission_progress',
      'systemBannerAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionUid = FirebaseAuth.instance.currentUser?.uid ??
        AppSessionService.currentUserId;
    if (sessionUid.isEmpty) return const AuthScreen();

    return Scaffold(
      backgroundColor: _kThreadBg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _conversationStream,
        builder: (context, conversationSnapshot) {
          final conversationData =
              conversationSnapshot.data?.data() ?? const <String, dynamic>{};
          final typingBy = (conversationData['typingBy'] as Map?)
                  ?.map((k, v) => MapEntry('$k', v == true)) ??
              const <String, bool>{};
          _participantIds =
              ((conversationData['participants'] as List?) ?? const [])
                  .map((e) => '$e')
                  .where((e) => e.trim().isNotEmpty)
                  .toList();
          final blockedBy =
              ((conversationData['blockedBy'] as List?) ?? const <dynamic>[])
                  .map((e) => '$e')
                  .toSet();
          final isBlockedByCurrentUser = blockedBy.contains(sessionUid);
          final isOtherTyping = typingBy.entries.any(
            (entry) => entry.key != sessionUid && entry.value,
          );
          final systemBannerText =
              (conversationData['systemBannerText'] as String?)?.trim();
          final systemBannerKind =
              (conversationData['systemBannerKind'] as String?)?.trim() ?? '';
          final systemBannerAt =
              (conversationData['systemBannerAt'] as Timestamp?)?.toDate();
          final conversationType =
              (conversationData['type'] as String?)?.trim() ?? 'intervenant';
          final currentAccountType =
              (AppSessionService.currentUserData['accountType'] as String?)
                      ?.trim()
                      .toLowerCase() ??
                  '';
          final threadTitle =
              ((conversationData['title'] as String?)?.trim().isNotEmpty ??
                      false)
                  ? (conversationData['title'] as String).trim()
                  : widget.title;
          final threadSubtitle = isOtherTyping
              ? 'En train d\'ecrire...'
              : conversationType == 'team'
                  ? _buildGroupSubtitle(conversationData)
                  : widget.subtitle;
          final threadAvatarUrl =
              VpsMediaService.resolveProfileImageUrl(conversationData) ??
                  widget.avatarUrl;
          final shouldShowStoredBanner = systemBannerText != null &&
              systemBannerText.isNotEmpty &&
              systemBannerAt != null &&
              DateTime.now().difference(systemBannerAt).inSeconds <= 12;

          final bannerVisible =
              _ephemeralBannerText != null || shouldShowStoredBanner;
          final topInset = MediaQuery.paddingOf(context).top;

          final topContentPadding = MediaQuery.paddingOf(context).top +
              _kThreadHeaderHeight +
              (bannerVisible ? 34 : 10);

          return Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        _kChatBackgroundAsset,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.26),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        final docs = snapshot.data?.docs ?? const [];
                        unawaited(
                          _markIncomingMessagesSeen(docs, sessionUid),
                        );
                        if (docs.isNotEmpty) {
                          final latest = docs.last;
                          final latestData = latest.data();
                          if (latestData['senderId'] != sessionUid &&
                              _lastIncomingMessageId != latest.id) {
                            _lastIncomingMessageId = latest.id;
                            SystemSound.play(SystemSoundType.click);
                          }
                        }
                        if (docs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 34),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 18,
                                    sigmaY: 18,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 20,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.10,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'Commencez la conversation avec un message, une photo, une adresse ou un vocal.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withValues(
                                          alpha: 0.70,
                                        ),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final missionStripExtra = _activeMissionsCount > 0
                            ? (_missionsMinimized ? 48.0 : 160.0)
                            : 0.0;
                        return ListView.builder(
                          reverse: true,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            topContentPadding,
                            16,
                            118 + missionStripExtra,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[docs.length - 1 - index];
                            final data = doc.data();
                            final messageType =
                                (data['messageType'] as String?)?.trim() ?? '';
                            if (messageType == 'system' ||
                                messageType == 'member_removed' ||
                                messageType == 'member_added') {
                              return _InlineSystemCard(
                                text: (data['text'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? (data['text'] as String).trim()
                                    : 'Mise a jour du groupe',
                                icon: messageType == 'member_removed'
                                    ? LucideIcons.user
                                    : messageType == 'member_added'
                                        ? LucideIcons.userPlus
                                        : LucideIcons.pin,
                                accent: messageType == 'member_removed'
                                    ? const Color(0xFFFF8A7A)
                                    : messageType == 'member_added'
                                        ? const Color(0xFF22C55E)
                                        : kAuthGold,
                              );
                            }
                            final isMine = data['senderId'] == sessionUid;
                            final senderId =
                                (data['senderId'] as String?)?.trim() ?? '';
                            return FutureBuilder<_MessageSenderSummary?>(
                              future: conversationType == 'team' && !isMine
                                  ? _loadSenderSummary(senderId)
                                  : Future.value(null),
                              builder: (context, senderSnapshot) {
                                final sender = senderSnapshot.data;
                                return _MessageBubble(
                                  key: ValueKey(doc.id),
                                  senderName: sender?.name ?? widget.title,
                                  senderAvatarBase64: sender?.avatarBase64,
                                  senderAvatarUrl: sender?.avatarUrl,
                                  senderRoleBadge: sender?.roleBadge,
                                  senderApartmentBadge: sender?.apartmentBadge,
                                  showSenderHeader:
                                      conversationType == 'team' && !isMine,
                                  messageId: doc.id,
                                  conversationId: widget.conversationId,
                                  isMine: isMine,
                                  text: (data['text'] as String?)?.trim() ?? '',
                                  imageUrl:
                                      VpsMediaService.normalizeMediaUrlSync(
                                    (data['imageUrl'] as String?)?.trim(),
                                  ),
                                  imageBase64:
                                      (data['imageBase64'] as String?)?.trim(),
                                  audioUrl:
                                      VpsMediaService.normalizeMediaUrlSync(
                                    (data['audioUrl'] as String?)?.trim(),
                                  ),
                                  audioDurationMs:
                                      (data['audioDurationMs'] as num?)
                                          ?.toInt(),
                                  audioWaveform:
                                      ((data['audioWaveform'] as List?) ??
                                              const [])
                                          .map((e) => (e as num).toInt())
                                          .toList(),
                                  address: (data['address'] as String?)?.trim(),
                                  latitude:
                                      (data['latitude'] as num?)?.toDouble(),
                                  longitude:
                                      (data['longitude'] as num?)?.toDouble(),
                                  fileIds:
                                      ((data['fileIds'] as List?) ?? const [])
                                          .map((e) => '$e')
                                          .toList(),
                                  deliveredTo:
                                      ((data['deliveredTo'] as List?) ??
                                              const [])
                                          .map((e) => '$e')
                                          .toList(),
                                  seenBy:
                                      ((data['seenBy'] as List?) ?? const [])
                                          .map((e) => '$e')
                                          .toList(),
                                  reaction:
                                      (data['reaction'] as String?)?.trim(),
                                  reactionByUserId:
                                      (data['reactionByUserId'] as String?)
                                          ?.trim(),
                                  createdAt: (data['createdAt'] as Timestamp?)
                                      ?.toDate(),
                                  onDelete: (fileIds) => _deleteMessage(
                                    doc.id,
                                    fileIds: fileIds,
                                  ),
                                  onReact: (reaction) =>
                                      _reactToMessage(doc.id, reaction),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _ThreadHeader(
                  title: threadTitle,
                  subtitle: threadSubtitle,
                  avatarBase64: widget.avatarBase64,
                  avatarUrl: threadAvatarUrl,
                  isAvailable: widget.isAvailable,
                  onMenuTap: _showChatOptionsSheet,
                  onInfoTap: () => _openChatInfoScreen(conversationData),
                ),
              ),
              Positioned(
                top: topInset + 72,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: true,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: (_ephemeralBannerText != null ||
                              shouldShowStoredBanner)
                          ? _SystemBanner(
                              key: ValueKey(
                                _ephemeralBannerText ?? systemBannerText ?? '',
                              ),
                              text: _ephemeralBannerText ?? systemBannerText!,
                              kind: systemBannerKind,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: isBlockedByCurrentUser
                    ? _BlockedConversationNotice(
                        onUnblock: () async {
                          await _conversationRef.set({
                            'blockedBy': FieldValue.arrayRemove([sessionUid]),
                          }, SetOptions(merge: true));
                        },
                        onDeleteConversation: _clearChatHistory,
                      )
                    : _ThreadComposer(
                        controller: _controller,
                        isSending: _isSending,
                        sendingLabel: _sendingLabel,
                        isRecording: _isRecording,
                        isRecordLocked: _isRecordLocked,
                        isRecordPaused: _isRecordPaused,
                        showRecordComposer: _showRecordComposer,
                        recordingElapsed: _recordingElapsed,
                        recordingWaveform: _recordingWaveform,
                        holdDx: _holdDx,
                        holdDy: _holdDy,
                        onChanged: _handleComposerChanged,
                        onAttachTap: _openAttachmentPicker,
                        onCameraTap: () =>
                            _pickAndSendImage(ImageSource.camera),
                        onSendTap: _sendText,
                        onMicTap: _toggleRecording,
                        onMicPressStart: () => _startRecording(
                          locked: false,
                          fromHold: true,
                        ),
                        onMicPressMove: (dx, dy) async {
                          if (!_isRecording || _isRecordLocked) return;
                          setState(() {
                            _holdDx = dx;
                            _holdDy = dy;
                          });
                          if (dx < -110) {
                            _recordCanceledByGesture = true;
                            await _cancelRecording();
                          } else if (dy < -80) {
                            setState(() {
                              _isRecordLocked = true;
                              _holdDx = 0;
                              _holdDy = 0;
                            });
                          }
                        },
                        onMicPressEnd: () async {
                          if (!_isRecording) return;
                          if (_recordCanceledByGesture) {
                            _recordCanceledByGesture = false;
                            return;
                          }
                          if (!_isRecordLocked) {
                            await _stopAndSendRecording();
                          }
                        },
                        onRecordDelete: _cancelRecording,
                        onRecordPauseResume: _pauseResumeRecording,
                        onRecordSend: _stopAndSendRecording,
                        missionStrip: _missionsMinimized
                            ? _MissionsCollapsedPill(
                                count: _activeMissionsCount,
                                onExpand: () => setState(
                                  () => _missionsMinimized = false,
                                ),
                              )
                            : _PinnedMissionsStrip(
                                stream: _tasksRef
                                    .orderBy('createdAt', descending: true)
                                    .limit(8)
                                    .snapshots(),
                                currentUid: sessionUid,
                                currentAccountType: currentAccountType,
                                conversationType: conversationType,
                                onComplete: _completeMission,
                                onAccept: _acceptMission,
                                onDelete: _removeMission,
                                onMinimize: () => setState(
                                  () => _missionsMinimized = true,
                                ),
                              ),
                        canCreateMission: (conversationType == 'team' ||
                                conversationType == 'intervenant') &&
                            currentAccountType != 'concierge' &&
                            currentAccountType != 'worker' &&
                            currentAccountType != 'stayfix_job',
                        onMissionTap: _openCreateTaskSheet,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
    required this.isAvailable,
    required this.onMenuTap,
    required this.onInfoTap,
  });

  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;
  final bool isAvailable;
  final VoidCallback onMenuTap;
  final VoidCallback onInfoTap;

  @override
  Widget build(BuildContext context) {
    Uint8List? photoBytes;
    if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        photoBytes = base64Decode(avatarBase64!);
      } catch (_) {}
    }

    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 12),
      decoration: BoxDecoration(
        color: _kThreadSurface,
        border: const Border(bottom: BorderSide(color: _kThreadBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          ),
          Expanded(
            child: InkWell(
              onTap: onInfoTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: kAuthGold.withValues(alpha: 0.45)),
                            color: const Color(0xFF1E1E1E),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: avatarUrl != null && avatarUrl!.isNotEmpty
                              ? Image.network(
                                  avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      photoBytes != null
                                          ? Image.memory(photoBytes,
                                              fit: BoxFit.cover)
                                          : _HeaderInitial(title: title),
                                )
                              : photoBytes != null
                                  ? Image.memory(photoBytes, fit: BoxFit.cover)
                                  : _HeaderInitial(title: title),
                        ),
                        if (isAvailable)
                          Positioned(
                            right: 0,
                            bottom: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _kThreadSurface, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
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
          GestureDetector(
            onTap: onMenuTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(color: _kThreadBorder),
              ),
              child: const Icon(
                LucideIcons.moreVertical,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemBanner extends StatelessWidget {
  const _SystemBanner({
    super.key,
    required this.text,
    this.kind = '',
  });

  final String text;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final palette = _resolveSystemBannerPalette(kind);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: palette.fill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: palette.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSystemCard extends StatelessWidget {
  const _InlineSystemCard({
    required this.text,
    required this.icon,
    required this.accent,
  });

  final String text;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accent, size: 16),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderInitial extends StatelessWidget {
  const _HeaderInitial({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: kAuthGold,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BubbleShell extends StatelessWidget {
  const _BubbleShell({
    required this.isMine,
    required this.color,
    required this.borderColor,
    required this.padding,
    required this.child,
  });

  final bool isMine;
  final Color color;
  final Color borderColor;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isMine ? 22 : 8),
              bottomRight: Radius.circular(isMine ? 8 : 22),
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          right: isMine ? 0 : null,
          left: isMine ? null : 0,
          bottom: 6,
          child: CustomPaint(
            size: const Size(14, 14),
            painter: _BubbleTailPainter(
              color: color,
              borderColor: borderColor,
              isMine: isMine,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({
    required this.color,
    required this.borderColor,
    required this.isMine,
  });

  final Color color;
  final Color borderColor;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (isMine) {
      path
        ..moveTo(size.width, size.height)
        ..lineTo(2, size.height)
        ..quadraticBezierTo(size.width - 1, size.height - 1, size.width, 1)
        ..close();
    } else {
      path
        ..moveTo(0, 1)
        ..quadraticBezierTo(1, size.height - 1, size.width - 2, size.height)
        ..lineTo(0, size.height)
        ..close();
    }

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.isMine != isMine;
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.senderName,
    this.senderAvatarBase64,
    this.senderAvatarUrl,
    this.senderRoleBadge,
    this.senderApartmentBadge,
    this.showSenderHeader = false,
    required this.messageId,
    required this.conversationId,
    required this.isMine,
    required this.text,
    required this.imageUrl,
    required this.imageBase64,
    required this.audioUrl,
    required this.audioDurationMs,
    required this.audioWaveform,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.fileIds,
    required this.deliveredTo,
    required this.seenBy,
    required this.reaction,
    required this.reactionByUserId,
    required this.createdAt,
    required this.onDelete,
    required this.onReact,
  });

  final String senderName;
  final String? senderAvatarBase64;
  final String? senderAvatarUrl;
  final String? senderRoleBadge;
  final String? senderApartmentBadge;
  final bool showSenderHeader;
  final String messageId;
  final String conversationId;
  final bool isMine;
  final String text;
  final String? imageUrl;
  final String? imageBase64;
  final String? audioUrl;
  final int? audioDurationMs;
  final List<int> audioWaveform;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<String> fileIds;
  final List<String> deliveredTo;
  final List<String> seenBy;
  final String? reaction;
  final String? reactionByUserId;
  final DateTime? createdAt;
  final Future<void> Function(List<String> fileIds) onDelete;
  final Future<void> Function(String reaction) onReact;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _cachedAudioPath;
  bool _showReactionPop = false;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<String?> _ensureLocalAudioPath() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return null;
    if (_cachedAudioPath != null && await File(_cachedAudioPath!).exists()) {
      return _cachedAudioPath;
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('audio download failed');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/chat_audio_${widget.messageId}_${widget.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}.m4a';
    await File(path).writeAsBytes(response.bodyBytes, flush: true);
    _cachedAudioPath = path;
    return path;
  }

  Future<void> _toggleAudio() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;

    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
      return;
    }

    try {
      final localPath = await _ensureLocalAudioPath();
      if (localPath == null) return;
      await _player.play(
        DeviceFileSource(localPath),
        mode: PlayerMode.mediaPlayer,
        volume: 1.0,
      );
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _duration = widget.audioDurationMs != null
              ? Duration(milliseconds: widget.audioDurationMs!)
              : _duration;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de lire ce vocal pour le moment.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }

  Future<void> _seekAudio(double fraction) async {
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : (widget.audioDurationMs ?? 0);
    if (totalMs <= 0) return;
    final targetMs = (totalMs * fraction.clamp(0.0, 1.0)).round();
    try {
      if (!_isPlaying && _duration == Duration.zero) {
        final url = widget.audioUrl;
        if (url == null || url.isEmpty) return;
        try {
          await _player.setSource(UrlSource(url));
        } catch (_) {
          final localPath = await _ensureLocalAudioPath();
          if (localPath == null) return;
          await _player.setSource(DeviceFileSource(localPath));
        }
      }
    } catch (_) {
      return;
    }
    await _player.seek(Duration(milliseconds: targetMs));
    if (!_isPlaying) {
      try {
        await _player.resume();
      } catch (_) {
        await _toggleAudio();
      }
    }
  }

  Future<void> _handleQuickReaction() async {
    setState(() => _showReactionPop = true);
    Future<void>.delayed(const Duration(milliseconds: 760), () {
      if (!mounted) return;
      setState(() => _showReactionPop = false);
    });
    await widget.onReact('heart');
  }

  Future<void> _showReactionTray(LongPressStartDetails details) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final origin = renderBox.localToGlobal(Offset.zero);
    final rect = origin & renderBox.size;
    final reaction = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reactions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StayFixReactionOverlay(
          targetRect: rect,
          selectedReaction: widget.reaction,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: child),
        );
      },
    );
    if (reaction != null && reaction.isNotEmpty) {
      await widget.onReact(reaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? imageBytes;
    Uint8List? senderAvatarBytes;
    if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      try {
        imageBytes = base64Decode(widget.imageBase64!);
      } catch (_) {}
    }
    if (widget.senderAvatarBase64 != null &&
        widget.senderAvatarBase64!.isNotEmpty) {
      try {
        senderAvatarBytes = base64Decode(widget.senderAvatarBase64!);
      } catch (_) {}
    }

    final background = widget.isMine ? kAuthGold : _kThreadPeerBubble;
    final foreground = widget.isMine ? Colors.black : Colors.white;
    final hasText = widget.text.isNotEmpty;
    final hasAddress = widget.address != null && widget.address!.isNotEmpty;
    final hasAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    final hasImage = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ||
        imageBytes != null;
    final imageOnly = hasImage && !hasText && !hasAudio && !hasAddress;
    final bubbleColor = imageOnly ? Colors.transparent : background;
    final isSeenByOther = widget.seenBy.length > 1;
    final isDeliveredToOther = widget.deliveredTo.length > 1;

    final reaction = widget.reaction;

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onDoubleTap: _handleQuickReaction,
        onLongPressStart: _showReactionTray,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: () {
              // Build the shared Stack content.
              final stackContent = Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: reaction != null && reaction.isNotEmpty ? 10 : 0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: widget.isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (hasImage) ...[
                          _MessageImage(
                            imageUrl: widget.imageUrl,
                            imageBytes: imageBytes,
                            isMine: widget.isMine,
                            createdAt: widget.createdAt,
                            onOpen: () => _openImagePreview(imageBytes),
                          ),
                          if (hasText || hasAudio || hasAddress)
                            const SizedBox(height: 6),
                        ],
                        if (hasText || hasAudio || hasAddress)
                          _BubbleShell(
                            isMine: widget.isMine,
                            color: bubbleColor,
                            borderColor: widget.isMine
                                ? kAuthGold.withValues(alpha: 0.60)
                                : Colors.white.withValues(alpha: 0.08),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasAddress)
                                  _AddressCard(
                                      widget: widget, foreground: foreground),
                                if (hasAddress &&
                                    (hasImage || hasText || hasAudio))
                                  const SizedBox(height: 10),
                                if (hasAudio)
                                  _AudioBubbleRow(
                                    isMine: widget.isMine,
                                    foreground: foreground,
                                    isPlaying: _isPlaying,
                                    durationMs: widget.audioDurationMs,
                                    waveform: widget.audioWaveform,
                                    progressMs: _position.inMilliseconds,
                                    activeDurationMs:
                                        _duration.inMilliseconds > 0
                                            ? _duration.inMilliseconds
                                            : widget.audioDurationMs,
                                    onTap: _toggleAudio,
                                    onSeek: _seekAudio,
                                  ),
                                if (hasAudio && hasText)
                                  const SizedBox(height: 8),
                                if (hasText)
                                  Text(
                                    widget.text,
                                    style: GoogleFonts.inter(
                                      color: foreground,
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(widget.createdAt),
                                        style: GoogleFonts.inter(
                                          color: foreground.withValues(
                                              alpha: 0.70),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (widget.isMine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          isSeenByOther
                                              ? Icons.done_all_rounded
                                              : isDeliveredToOther
                                                  ? Icons.done_all_rounded
                                                  : Icons.done_rounded,
                                          size: 15,
                                          color: isSeenByOther
                                              ? _kSeenBlue
                                              : foreground.withValues(
                                                  alpha: 0.72),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (imageOnly)
                          _MessageStatusOverlay(
                            isMine: widget.isMine,
                            createdAt: widget.createdAt,
                            isSeenByOther: isSeenByOther,
                            isDeliveredToOther: isDeliveredToOther,
                          ),
                      ],
                    ),
                  ),
                  if (reaction != null && reaction.isNotEmpty)
                    Positioned(
                      top: 0,
                      right: widget.isMine ? 12 : null,
                      left: widget.isMine ? null : 12,
                      child: StayFixReactionBadge(
                        reaction: reaction,
                        highlighted: _showReactionPop && reaction == 'heart',
                      ),
                    ),
                  if (_showReactionPop)
                    Positioned(
                      top: 18,
                      right: widget.isMine ? -10 : null,
                      left: widget.isMine ? null : -10,
                      child: IgnorePointer(
                        child: AnimatedScale(
                          scale: _showReactionPop ? 1 : 0.6,
                          duration: const Duration(milliseconds: 180),
                          child: const _StayFixHeartBurst(),
                        ),
                      ),
                    ),
                ],
              );

              // Text-only: shrink bubble to text width.
              // Audio: force full max-width. Everything else: natural width.
              if (hasText && !hasAudio && !hasAddress && !hasImage) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showSenderHeader)
                      _GroupSenderHeader(
                        name: widget.senderName,
                        avatarBytes: senderAvatarBytes,
                        avatarUrl: widget.senderAvatarUrl,
                        roleBadge: widget.senderRoleBadge,
                        apartmentBadge: widget.senderApartmentBadge,
                      ),
                    IntrinsicWidth(child: stackContent),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showSenderHeader)
                    _GroupSenderHeader(
                      name: widget.senderName,
                      avatarBytes: senderAvatarBytes,
                      avatarUrl: widget.senderAvatarUrl,
                      roleBadge: widget.senderRoleBadge,
                      apartmentBadge: widget.senderApartmentBadge,
                    ),
                  SizedBox(
                    width: hasAudio
                        ? MediaQuery.of(context).size.width * 0.78
                        : null,
                    child: stackContent,
                  ),
                ],
              );
            }(),
          ),
        ),
      ),
    );
  }

  Future<void> _openImagePreview(Uint8List? imageBytes) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewScreen(
            senderName: widget.senderName,
            timeLabel: _formatTime(widget.createdAt),
            imageUrl: widget.imageUrl,
            imageBytes: imageBytes,
            onDelete: () => widget.onDelete(widget.fileIds),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime? value) {
    if (value == null) return '';
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.widget,
    required this.foreground,
  });

  final _MessageBubble widget;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = widget.latitude != null && widget.longitude != null
            ? Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}',
              )
            : Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(widget.address ?? '')}',
              );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: widget.isMine
                  ? Colors.black.withValues(alpha: 0.10)
                  : kAuthGold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.mapPin,
              color: widget.isMine ? Colors.black : kAuthGold,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adresse partagee',
                  style: GoogleFonts.inter(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.address!,
                  style: GoogleFonts.inter(
                    color: foreground.withValues(alpha: 0.86),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Touchez pour ouvrir dans Maps',
                  style: GoogleFonts.inter(
                    color: foreground.withValues(alpha: 0.66),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.latitude != null && widget.longitude != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
                    style: GoogleFonts.inter(
                      color: foreground.withValues(alpha: 0.60),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupSenderHeader extends StatelessWidget {
  const _GroupSenderHeader({
    required this.name,
    required this.avatarBytes,
    required this.avatarUrl,
    this.roleBadge,
    this.apartmentBadge,
  });

  final String name;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final String? roleBadge;
  final String? apartmentBadge;

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if ((avatarUrl ?? '').trim().isNotEmpty) {
      avatar = Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => avatarBytes != null
            ? Image.memory(avatarBytes!, fit: BoxFit.cover)
            : _HeaderInitial(title: name),
      );
    } else if (avatarBytes != null) {
      avatar = Image.memory(avatarBytes!, fit: BoxFit.cover);
    } else {
      avatar = _HeaderInitial(title: name);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1E1E),
              border: Border.all(color: kAuthGold.withValues(alpha: 0.38)),
            ),
            child: avatar,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((roleBadge ?? '').trim().isNotEmpty ||
                    (apartmentBadge ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if ((roleBadge ?? '').trim().isNotEmpty)
                        _SenderBadge(
                          label: roleBadge!.trim(),
                          background: kAuthGold.withValues(alpha: 0.16),
                          border: kAuthGold.withValues(alpha: 0.36),
                          foreground: kAuthGold,
                        ),
                      if ((apartmentBadge ?? '').trim().isNotEmpty)
                        _SenderBadge(
                          label: apartmentBadge!.trim(),
                          background: Colors.white.withValues(alpha: 0.06),
                          border: Colors.white.withValues(alpha: 0.12),
                          foreground: Colors.white,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderBadge extends StatelessWidget {
  const _SenderBadge({
    required this.label,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color border;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AudioBubbleRow extends StatelessWidget {
  const _AudioBubbleRow({
    required this.isMine,
    required this.foreground,
    required this.isPlaying,
    required this.durationMs,
    required this.waveform,
    required this.progressMs,
    required this.activeDurationMs,
    required this.onTap,
    required this.onSeek,
  });

  final bool isMine;
  final Color foreground;
  final bool isPlaying;
  final int? durationMs;
  final List<int> waveform;
  final int progressMs;
  final int? activeDurationMs;
  final VoidCallback onTap;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final totalMs = (activeDurationMs != null && activeDurationMs! > 0)
        ? activeDurationMs!
        : (durationMs ?? 0);
    final progress = totalMs <= 0
        ? 0.0
        : (progressMs.clamp(0, totalMs) / totalMs).clamp(0.0, 1.0);
    final bars = waveform.isNotEmpty ? waveform : _waveBars(totalMs);

    final accent = isMine ? Colors.black : kAuthGold;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isMine
                  ? Colors.black.withValues(alpha: 0.12)
                  : kAuthGold.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: isMine
                    ? Colors.black.withValues(alpha: 0.14)
                    : kAuthGold.withValues(alpha: 0.34),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              isPlaying ? LucideIcons.pause : LucideIcons.play,
              color: accent,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  onSeek(details.localPosition.dx / width);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 28,
                      child: Row(
                        children: [
                          for (var i = 0; i < bars.length; i++) ...[
                            Expanded(
                              child: Align(
                                alignment: Alignment.center,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  width: 3.0,
                                  height: bars[i].toDouble().clamp(8, 28),
                                  decoration: BoxDecoration(
                                    color: (i / bars.length) <= progress
                                        ? accent
                                        : foreground.withValues(
                                            alpha: 0.22,
                                          ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                            if (i != bars.length - 1) const SizedBox(width: 2),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatDuration(progressMs > 0 ? progressMs : durationMs),
              style: GoogleFonts.inter(
                color: foreground.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDuration(totalMs),
              style: GoogleFonts.inter(
                color: foreground.withValues(alpha: 0.56),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static List<int> _waveBars(int totalMs) {
    final seed = totalMs <= 0 ? 17 : totalMs;
    return List<int>.generate(28, (index) {
      final base = ((seed ~/ (index + 3)) + index * 7) % 17;
      return 8 + base;
    });
  }

  static String _formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '0:00';
    final totalSeconds = (durationMs / 1000).round();
    final minutes = (totalSeconds ~/ 60).toString();
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MessageStatusOverlay extends StatelessWidget {
  const _MessageStatusOverlay({
    required this.isMine,
    required this.createdAt,
    required this.isSeenByOther,
    required this.isDeliveredToOther,
  });

  final bool isMine;
  final DateTime? createdAt;
  final bool isSeenByOther;
  final bool isDeliveredToOther;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.only(top: 6, right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _MessageBubbleState._formatTime(createdAt),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isMine) ...[
              const SizedBox(width: 4),
              Icon(
                isSeenByOther
                    ? Icons.done_all_rounded
                    : isDeliveredToOther
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                size: 15,
                color: isSeenByOther
                    ? _kSeenBlue
                    : Colors.white.withValues(alpha: 0.82),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({
    required this.imageUrl,
    required this.imageBytes,
    required this.isMine,
    required this.createdAt,
    required this.onOpen,
  });

  final String? imageUrl;
  final Uint8List? imageBytes;
  final bool isMine;
  final DateTime? createdAt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(
                minHeight: 160,
                maxHeight: 340,
                minWidth: 180,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isMine
                      ? kAuthGold.withValues(alpha: 0.20)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? InteractiveViewer(
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return _MediaPlaceholder(
                            label: 'Chargement photo...',
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: kAuthGold,
                              value: progress.expectedTotalBytes == null
                                  ? null
                                  : progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const _MediaPlaceholder(
                            label: 'Impossible de charger cette photo',
                            child: Icon(
                              LucideIcons.imageOff,
                              color: Colors.white70,
                              size: 28,
                            ),
                          );
                        },
                      ),
                    )
                  : imageBytes != null
                      ? InteractiveViewer(
                          child: Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        )
                      : const _MediaPlaceholder(
                          label: 'Aucune image disponible',
                          child: Icon(
                            LucideIcons.imageOff,
                            color: Colors.white70,
                            size: 28,
                          ),
                        ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _MessageBubbleState._formatTime(createdAt),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewScreen extends StatefulWidget {
  const _ImagePreviewScreen({
    required this.senderName,
    required this.timeLabel,
    required this.imageUrl,
    required this.imageBytes,
    required this.onDelete,
  });

  final String senderName;
  final String timeLabel;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Future<void> Function() onDelete;

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _downloadImage() async {
    try {
      Uint8List bytes;
      if (widget.imageBytes != null) {
        bytes = widget.imageBytes!;
      } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
        final response = await http.get(Uri.parse(widget.imageUrl!));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('download failed');
        }
        bytes = response.bodyBytes;
      } else {
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/stayfix_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image enregistree dans $path',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de telecharger cette image.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                  ? Image.network(
                      widget.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const _MediaPlaceholder(
                          label: 'Impossible de charger cette photo',
                          child: Icon(
                            LucideIcons.imageOff,
                            color: Colors.white70,
                            size: 36,
                          ),
                        );
                      },
                    )
                  : widget.imageBytes != null
                      ? Image.memory(widget.imageBytes!, fit: BoxFit.contain)
                      : const _MediaPlaceholder(
                          label: 'Image indisponible',
                          child: Icon(
                            LucideIcons.imageOff,
                            color: Colors.white70,
                            size: 36,
                          ),
                        ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final animation = CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              );
              return Transform.translate(
                offset: Offset(0, -42 * (1 - animation.value)),
                child: Opacity(
                  opacity: animation.value,
                  child: child,
                ),
              );
            },
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        LucideIcons.x,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.senderName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.timeLabel,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      color: Colors.white,
                      icon: const Icon(
                        LucideIcons.moreVertical,
                        color: Colors.white,
                      ),
                      onSelected: (value) async {
                        if (value == 'delete') {
                          final navigator = Navigator.of(context);
                          await widget.onDelete();
                          if (!mounted) return;
                          navigator.pop();
                        } else if (value == 'download') {
                          await _downloadImage();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'download',
                          child: Text('Download'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedMissionsStrip extends StatelessWidget {
  const _PinnedMissionsStrip({
    required this.stream,
    required this.currentUid,
    required this.currentAccountType,
    required this.conversationType,
    required this.onComplete,
    required this.onAccept,
    required this.onDelete,
    required this.onMinimize,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String currentUid;
  final String currentAccountType;
  final String conversationType;
  final Future<void> Function(String taskId, Map<String, dynamic> data)
      onComplete;
  final Future<void> Function(String taskId, Map<String, dynamic> data)
      onAccept;
  final Future<void> Function(String taskId, Map<String, dynamic> data)
      onDelete;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final isWorker = _isWorkerAccountType(currentAccountType);
        final docs = (snapshot.data?.docs ?? const []).where((doc) {
          final data = doc.data();
          final status = (data['status'] as String?)?.trim() ?? 'open';
          if (status == 'completed' || status == 'deleted') return false;
          final assignedMemberIds = _readStringList(data['assignedMemberIds']);
          final assignedToId = (data['assignedToId'] as String?)?.trim() ?? '';
          if (!isWorker) return true;
          if (assignedMemberIds.contains(currentUid)) return true;
          if (assignedMemberIds.isNotEmpty) return false;
          if (assignedToId.isNotEmpty) return assignedToId == currentUid;
          return true;
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.pin, size: 13, color: kAuthGold),
                  const SizedBox(width: 6),
                  Text(
                    'Missions actives',
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onMinimize,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.chevronDown,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: docs.map((doc) {
                  final data = doc.data();
                  final status = (data['status'] as String?)?.trim() ?? 'open';
                  final assignedToId =
                      (data['assignedToId'] as String?)?.trim() ?? '';
                  final assignedMemberIds = _readStringList(
                    data['assignedMemberIds'],
                  );
                  final assignedMemberNames = _readStringList(
                    data['assignedMemberNames'],
                  );
                  final completedByIds =
                      _readStringList(data['completedByIds']);
                  final createdBy =
                      (data['createdBy'] as String?)?.trim() ?? '';
                  final acceptedBy =
                      (data['acceptedBy'] as String?)?.trim() ?? '';
                  final targetCount = assignedMemberIds.isNotEmpty
                      ? assignedMemberIds.length
                      : (((data['targetCount'] as num?)?.toInt() ?? 0) > 0
                          ? (data['targetCount'] as num).toInt()
                          : (assignedToId.isNotEmpty ? 1 : 1));
                  final completedCount = completedByIds.isNotEmpty
                      ? completedByIds.length
                      : ((data['completedCount'] as num?)?.toInt() ?? 0);
                  final isCompleted =
                      status == 'completed' || completedCount >= targetCount;
                  final isLegacyAcceptFlow = conversationType ==
                          'intervenant' ||
                      (assignedMemberIds.isEmpty && assignedToId.isNotEmpty);
                  final workerEligible = createdBy != currentUid &&
                      (assignedMemberIds.contains(currentUid) ||
                          (assignedMemberIds.isEmpty &&
                              ((assignedToId.isNotEmpty &&
                                      assignedToId == currentUid) ||
                                  (assignedToId.isEmpty && isWorker))));
                  final canDelete = !isWorker;
                  final canAccept = isLegacyAcceptFlow &&
                      status == 'open' &&
                      workerEligible &&
                      acceptedBy.isEmpty;
                  final canComplete = isLegacyAcceptFlow
                      ? status == 'accepted' && acceptedBy == currentUid
                      : !isCompleted &&
                          workerEligible &&
                          !completedByIds.contains(currentUid);
                  final isInProgress = !isCompleted &&
                      (status == 'accepted' || completedCount > 0);
                  final progressLabel = '$completedCount/$targetCount';
                  final assigneeLabel = assignedMemberNames.isEmpty
                      ? (assignedToId.isNotEmpty &&
                              ((data['assignedToName'] as String?)
                                      ?.trim()
                                      .isNotEmpty ??
                                  false)
                          ? 'Pour ${(data['assignedToName'] as String).trim()}'
                          : 'Mission equipe')
                      : assignedMemberNames.length == 1
                          ? 'Pour ${assignedMemberNames.first}'
                          : 'Pour ${assignedMemberNames.length} membres';
                  final borderColor = isCompleted
                      ? const Color(0xFF22C55E).withValues(alpha: 0.58)
                      : isInProgress
                          ? kAuthGold.withValues(alpha: 0.5)
                          : _kThreadBorder;
                  final statusBg = isCompleted
                      ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                      : kAuthGold.withValues(alpha: 0.18);
                  final statusFg =
                      isCompleted ? const Color(0xFF86EFAC) : kAuthGold;
                  final statusText = isCompleted
                      ? 'Terminee'
                      : isInProgress
                          ? 'En cours'
                          : 'A faire';
                  return Container(
                    width: 240,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? LucideIcons.badgeCheck
                                  : LucideIcons.pin,
                              size: 14,
                              color: statusFg,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusText,
                                style: GoogleFonts.inter(
                                  color: statusFg,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                (data['title'] as String?)?.trim().isNotEmpty ==
                                        true
                                    ? (data['title'] as String).trim()
                                    : 'Mission',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (canDelete)
                              GestureDetector(
                                onTap: () => onDelete(doc.id, data),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _kThreadBorder),
                                  ),
                                  child: const Icon(
                                    LucideIcons.trash2,
                                    size: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if ((data['description'] as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 6),
                          Text(
                            (data['description'] as String).trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    assigneeLabel,
                                    style: GoogleFonts.inter(
                                      color: kAuthGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Progression $progressLabel',
                                    style: GoogleFonts.inter(
                                      color: isCompleted
                                          ? const Color(0xFF86EFAC)
                                          : Colors.white
                                              .withValues(alpha: 0.68),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canAccept)
                              GestureDetector(
                                onTap: () => onAccept(doc.id, data),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: kAuthGold.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    'Accepter',
                                    style: GoogleFonts.inter(
                                      color: kAuthGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            if (canComplete)
                              GestureDetector(
                                onTap: () => onComplete(doc.id, data),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? const Color(0xFF22C55E)
                                        : kAuthGold,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Terminer',
                                    style: GoogleFonts.inter(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MissionsCollapsedPill extends StatelessWidget {
  const _MissionsCollapsedPill({
    required this.count,
    required this.onExpand,
  });

  final int count;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onExpand,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kAuthGold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.pin, size: 13, color: kAuthGold),
            const SizedBox(width: 6),
            Text(
              '$count mission${count == 1 ? '' : 's'} active${count == 1 ? '' : 's'}',
              style: GoogleFonts.inter(
                color: kAuthGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(LucideIcons.chevronDown, size: 13, color: kAuthGold),
          ],
        ),
      ),
    );
  }
}

class _MissionHistoryScreen extends StatefulWidget {
  const _MissionHistoryScreen({
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<_MissionHistoryScreen> createState() => _MissionHistoryScreenState();
}

class _MissionHistoryScreenState extends State<_MissionHistoryScreen> {
  String _filter = 'ongoing';

  bool _matchesFilter(String status) {
    if (_filter == 'completed') return status == 'completed';
    if (_filter == 'deleted') return status == 'deleted';
    return status == 'open' || status == 'accepted';
  }

  String _filterLabel(String value) {
    switch (value) {
      case 'completed':
        return 'Terminees';
      case 'deleted':
        return 'Supprimees';
      default:
        return 'En cours';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('tasks')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: _kThreadBg,
      appBar: AppBar(
        backgroundColor: _kThreadBg,
        title: Text(
          'Missions',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in const ['ongoing', 'completed', 'deleted'])
                  ChoiceChip(
                    label: Text(_filterLabel(item)),
                    selected: _filter == item,
                    onSelected: (_) => setState(() => _filter = item),
                    selectedColor: kAuthGold,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    labelStyle: GoogleFonts.inter(
                      color: _filter == item ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: _filter == item
                          ? kAuthGold
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: tasksStream,
              builder: (context, snapshot) {
                final docs = (snapshot.data?.docs ?? const []).where((doc) {
                  final status =
                      (doc.data()['status'] as String?)?.trim() ?? 'open';
                  return _matchesFilter(status);
                }).toList();
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Aucune mission ${_filterLabel(_filter).toLowerCase()}.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 14,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final status =
                        (data['status'] as String?)?.trim() ?? 'open';
                    final assignedNames =
                        _readStringList(data['assignedMemberNames']);
                    final completedCount =
                        (_readStringList(data['completedByIds'])).length;
                    final targetCount = assignedNames.isNotEmpty
                        ? assignedNames.length
                        : (((data['targetCount'] as num?)?.toInt() ?? 0) > 0
                            ? (data['targetCount'] as num).toInt()
                            : 1);
                    final accent = status == 'completed'
                        ? const Color(0xFF22C55E)
                        : status == 'deleted'
                            ? const Color(0xFFFF7B7B)
                            : kAuthGold;
                    final badge = status == 'completed'
                        ? 'Terminee'
                        : status == 'deleted'
                            ? 'Supprimee'
                            : status == 'accepted'
                                ? 'Acceptee'
                                : 'Ouverte';
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _kThreadCard,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.36),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (data['title'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? (data['title'] as String).trim()
                                      : 'Mission',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  badge,
                                  style: GoogleFonts.inter(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if ((data['description'] as String?)
                                  ?.trim()
                                  .isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            Text(
                              (data['description'] as String).trim(),
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.72),
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            assignedNames.isEmpty
                                ? 'Mission equipe'
                                : 'Assignes: ${assignedNames.join(', ')}',
                            style: GoogleFonts.inter(
                              color: kAuthGold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Progression: $completedCount/$targetCount',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedConversationNotice extends StatelessWidget {
  const _BlockedConversationNotice({
    required this.onUnblock,
    required this.onDeleteConversation,
  });

  final Future<void> Function() onUnblock;
  final Future<void> Function() onDeleteConversation;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kThreadBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vous avez bloque cette personne.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async => onDeleteConversation(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x55FF7D7D)),
                      foregroundColor: const Color(0xFFFF7D7D),
                    ),
                    child: const Text('Supprimer la discussion'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async => onUnblock(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAuthGold,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Debloquer cette personne'),
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

class _CreateMissionSheet extends StatefulWidget {
  const _CreateMissionSheet({
    required this.conversationId,
    required this.managerUid,
    required this.onCreate,
  });

  final String conversationId;
  final String managerUid;
  final Future<void> Function({
    required String title,
    required String description,
    required List<String> assignedMemberIds,
    required List<String> assignedMemberNames,
  }) onCreate;

  @override
  State<_CreateMissionSheet> createState() => _CreateMissionSheetState();
}

class _CreateMissionSheetState extends State<_CreateMissionSheet> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final Set<String> _selectedAssigneeIds = <String>{};
  List<_MissionAssigneeOption> _assignees = const <_MissionAssigneeOption>[];
  bool _loadingAssignees = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAssignees();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssignees() async {
    try {
      final conversationDoc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      final data = conversationDoc.data() ?? const <String, dynamic>{};
      final participantIds = _readStringList(data['participants']);
      final options = <_MissionAssigneeOption>[];
      for (final participantId in participantIds) {
        if (participantId == widget.managerUid) continue;
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(participantId)
            .get();
        final profileDoc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(participantId)
            .get();
        final userData = userDoc.data() ?? const <String, dynamic>{};
        final profileData = profileDoc.data() ?? const <String, dynamic>{};
        final accountType =
            (userData['accountType'] as String?)?.trim().toLowerCase() ?? '';
        if (!_isWorkerAccountType(accountType)) continue;
        final firstName = (userData['firstName'] as String?)?.trim() ?? '';
        final lastName = (userData['lastName'] as String?)?.trim() ?? '';
        final fullName = '$firstName $lastName'.trim();
        final fallback = (profileData['username'] as String?)?.trim() ??
            (userData['username'] as String?)?.trim() ??
            'Membre';
        final apartmentId = ((userData['apartmentId'] ??
                    userData['propertyId'] ??
                    userData['managedPropertyId']) as String?)
                ?.trim() ??
            '';
        String? apartmentBadge;
        if (apartmentId.isNotEmpty) {
          final apartmentDoc = await FirebaseFirestore.instance
              .collection('hotels')
              .doc(apartmentId)
              .get();
          apartmentBadge = (apartmentDoc.data()?['name'] as String?)?.trim();
        }
        options.add(
          _MissionAssigneeOption(
            id: participantId,
            name: fullName.isNotEmpty ? fullName : fallback,
            roleLabel: _resolveRoleBadge(accountType, userData),
            apartmentBadge: apartmentBadge,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _assignees = options;
        _loadingAssignees = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAssignees = false);
    }
  }

  Future<void> _openAssigneePicker() async {
    if (_loadingAssignees) return;
    final localSelection = <String>{..._selectedAssigneeIds};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: _kThreadBorder),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Choisir les membres qui recevront la mission',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selectionnez un ou plusieurs concierges ou intervenants du groupe.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: _assignees.isEmpty
                          ? Center(
                              child: Text(
                                'Aucun membre StayFix Job n est disponible dans ce groupe.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _assignees.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final option = _assignees[index];
                                final selected =
                                    localSelection.contains(option.id);
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      if (selected) {
                                        localSelection.remove(option.id);
                                      } else {
                                        localSelection.add(option.id);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: selected ? 0.10 : 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: selected
                                            ? kAuthGold.withValues(alpha: 0.5)
                                            : Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? kAuthGold
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: selected
                                                  ? kAuthGold
                                                  : Colors.white.withValues(
                                                      alpha: 0.32,
                                                    ),
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            LucideIcons.check,
                                            size: 12,
                                            color: selected
                                                ? Colors.black
                                                : Colors.transparent,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                option.name,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  _SenderBadge(
                                                    label: option.roleLabel,
                                                    background:
                                                        kAuthGold.withValues(
                                                            alpha: 0.16),
                                                    border:
                                                        kAuthGold.withValues(
                                                      alpha: 0.36,
                                                    ),
                                                    foreground: kAuthGold,
                                                  ),
                                                  if ((option.apartmentBadge ??
                                                          '')
                                                      .trim()
                                                      .isNotEmpty)
                                                    _SenderBadge(
                                                      label: option
                                                          .apartmentBadge!
                                                          .trim(),
                                                      background: Colors.white
                                                          .withValues(
                                                              alpha: 0.06),
                                                      border: Colors.white
                                                          .withValues(
                                                              alpha: 0.12),
                                                      foreground: Colors.white,
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
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedAssigneeIds
                              ..clear()
                              ..addAll(localSelection);
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAuthGold,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(
                          'Valider la selection',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final selectedOptions = _assignees
        .where((option) => _selectedAssigneeIds.contains(option.id))
        .toList();
    await widget.onCreate(
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      assignedMemberIds: selectedOptions.map((option) => option.id).toList(),
      assignedMemberNames:
          selectedOptions.map((option) => option.name).toList(),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: _kThreadBorder),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kAuthGold.withValues(alpha: 0.18),
                      const Color(0xFF1A1A1A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: kAuthGold.withValues(alpha: 0.24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nouvelle mission',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Epinglez une mission claire pour votre equipe StayFix Job avec un titre court et une consigne precise.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Titre de mission',
                  hintText: 'Ex. Verification electricite cuisine',
                  filled: true,
                  fillColor: Color(0xFF181818),
                  prefixIcon: Icon(LucideIcons.briefcase, color: kAuthGold),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionCtrl,
                maxLines: 3,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Consigne',
                  hintText:
                      'Expliquez exactement ce qui doit etre fait, verifie ou livre.',
                  filled: true,
                  fillColor: Color(0xFF181818),
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(LucideIcons.clipboardList, color: kAuthGold),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _openAssigneePicker,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _kThreadBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: kAuthGold.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.users,
                          color: kAuthGold,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choisir les membres qui recevront cette mission',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _loadingAssignees
                                  ? 'Chargement des membres du groupe...'
                                  : _selectedAssigneeIds.isEmpty
                                      ? 'Aucun membre selectionne. Sans selection, la mission reste visible pour toute l equipe.'
                                      : '${_selectedAssigneeIds.length} membre(s) selectionne(s)',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        LucideIcons.chevronRight,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedAssigneeIds.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _assignees
                        .where(
                          (option) => _selectedAssigneeIds.contains(option.id),
                        )
                        .map(
                          (option) => _SenderBadge(
                            label: option.name,
                            background: Colors.white.withValues(alpha: 0.06),
                            border: Colors.white.withValues(alpha: 0.12),
                            foreground: Colors.white,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAuthGold,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    _saving ? 'Creation...' : 'Epingler la mission',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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

class _ThreadComposer extends StatelessWidget {
  const _ThreadComposer({
    required this.controller,
    required this.isSending,
    required this.sendingLabel,
    required this.isRecording,
    required this.isRecordLocked,
    required this.isRecordPaused,
    required this.showRecordComposer,
    required this.recordingElapsed,
    required this.recordingWaveform,
    required this.holdDx,
    required this.holdDy,
    required this.onChanged,
    required this.onAttachTap,
    required this.onCameraTap,
    required this.onSendTap,
    required this.onMicTap,
    required this.onMicPressStart,
    required this.onMicPressMove,
    required this.onMicPressEnd,
    required this.onRecordDelete,
    required this.onRecordPauseResume,
    required this.onRecordSend,
    required this.missionStrip,
    required this.canCreateMission,
    required this.onMissionTap,
  });

  final TextEditingController controller;
  final bool isSending;
  final String? sendingLabel;
  final bool isRecording;
  final bool isRecordLocked;
  final bool isRecordPaused;
  final bool showRecordComposer;
  final Duration recordingElapsed;
  final List<int> recordingWaveform;
  final double holdDx;
  final double holdDy;
  final VoidCallback onChanged;
  final VoidCallback onAttachTap;
  final VoidCallback onCameraTap;
  final VoidCallback onSendTap;
  final VoidCallback onMicTap;
  final VoidCallback onMicPressStart;
  final void Function(double dx, double dy) onMicPressMove;
  final VoidCallback onMicPressEnd;
  final VoidCallback onRecordDelete;
  final VoidCallback onRecordPauseResume;
  final VoidCallback onRecordSend;
  final Widget missionStrip;
  final bool canCreateMission;
  final VoidCallback onMissionTap;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    final recordBars = recordingWaveform.isEmpty
        ? List<int>.filled(26, 10)
        : recordingWaveform;

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 14 + bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isRecording && !isRecordLocked)
            Positioned(
              right: 8,
              bottom: 72,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      holdDy < -80 ? LucideIcons.lock : LucideIcons.unlock,
                      color: holdDy < -80
                          ? const Color(0xFF8FD3FF)
                          : Colors.white.withValues(alpha: 0.72),
                      size: 16,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lock',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              missionStrip,
              if (missionStrip is! SizedBox) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: showRecordComposer
                          ? Container(
                              key: const ValueKey('recording'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _kThreadSurface,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: _kThreadBorder),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: onRecordDelete,
                                    child: Icon(
                                      LucideIcons.trash2,
                                      color:
                                          Colors.white.withValues(alpha: 0.74),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (!isRecordLocked) ...[
                                    Expanded(
                                      child: Text(
                                        holdDx < -60
                                            ? 'Relachez pour annuler'
                                            : holdDy < -50
                                                ? 'Verrouillage en cours...'
                                                : '<  Slide to cancel',
                                        style: GoogleFonts.inter(
                                          color: Colors.white
                                              .withValues(alpha: 0.74),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    GestureDetector(
                                      onTap: onRecordPauseResume,
                                      child: Icon(
                                        isRecordPaused
                                            ? LucideIcons.mic
                                            : LucideIcons.pause,
                                        color: const Color(0xFFFF6678),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            height: 24,
                                            child: Row(
                                              children: [
                                                for (var i = 0;
                                                    i < recordBars.length;
                                                    i++) ...[
                                                  Expanded(
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Container(
                                                        width: 2.4,
                                                        height: recordBars[i]
                                                            .toDouble(),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.84),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            999,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (i !=
                                                      recordBars.length - 1)
                                                    const SizedBox(width: 2),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDuration(recordingElapsed),
                                            style: GoogleFonts.inter(
                                              color: Colors.white
                                                  .withValues(alpha: 0.84),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : Row(
                              key: const ValueKey('composer'),
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: isSending ? null : onAttachTap,
                                  icon: Icon(
                                    LucideIcons.paperclip,
                                    color: Colors.white.withValues(alpha: 0.72),
                                    size: 20,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _kThreadSurface,
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(color: _kThreadBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: controller,
                                            onChanged: (_) => onChanged(),
                                            minLines: 1,
                                            maxLines: 5,
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                            cursorColor: kAuthGold,
                                            decoration: InputDecoration(
                                              hintText: 'Ajouter un message',
                                              hintStyle: GoogleFonts.inter(
                                                color: Colors.white.withValues(
                                                  alpha: 0.38,
                                                ),
                                                fontSize: 14,
                                              ),
                                              border: InputBorder.none,
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: !canCreateMission || isSending
                                              ? null
                                              : onMissionTap,
                                          child: Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: canCreateMission
                                                  ? kAuthGold.withValues(
                                                      alpha: 0.14)
                                                  : Colors.white
                                                      .withValues(alpha: 0.05),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: canCreateMission
                                                    ? kAuthGold.withValues(
                                                        alpha: 0.24)
                                                    : Colors.white.withValues(
                                                        alpha: 0.06),
                                              ),
                                            ),
                                            child: Icon(
                                              LucideIcons.pin,
                                              color: canCreateMission
                                                  ? kAuthGold
                                                  : Colors.white
                                                      .withValues(alpha: 0.28),
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: isSending ? null : onCameraTap,
                                          child: Icon(
                                            LucideIcons.camera,
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                            size: 20,
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
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: isSending
                        ? null
                        : (showRecordComposer
                            ? onRecordSend
                            : (hasText ? onSendTap : onMicTap)),
                    onLongPressStart: hasText
                        ? null
                        : (_) {
                            onMicPressStart();
                          },
                    onLongPressMoveUpdate: hasText
                        ? null
                        : (details) {
                            onMicPressMove(
                              details.offsetFromOrigin.dx,
                              details.offsetFromOrigin.dy,
                            );
                          },
                    onLongPressEnd: hasText
                        ? null
                        : (_) {
                            onMicPressEnd();
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color:
                            isRecording ? const Color(0xFFFF6678) : kAuthGold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isRecording
                                    ? const Color(0xFFFF6678)
                                    : kAuthGold)
                                .withValues(alpha: 0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                showRecordComposer
                                    ? LucideIcons.send
                                    : hasText
                                        ? LucideIcons.send
                                        : LucideIcons.mic,
                                color:
                                    isRecording ? Colors.white : Colors.black,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (sendingLabel != null && sendingLabel!.trim().isNotEmpty)
            Positioned(
              left: 12,
              right: 76,
              bottom: 66,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kThreadBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: kAuthGold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sendingLabel!,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _StayFixReactionOverlay extends StatelessWidget {
  const _StayFixReactionOverlay({
    required this.targetRect,
    required this.selectedReaction,
  });

  final Rect targetRect;
  final String? selectedReaction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const trayWidth = 332.0;
    final left = (targetRect.center.dx - (trayWidth / 2))
        .clamp(14.0, size.width - trayWidth - 14.0);
    final top = (targetRect.top - 88).clamp(
      MediaQuery.paddingOf(context).top + 6.0,
      size.height - 180.0,
    );
    final pointerLeft =
        (targetRect.center.dx - left - 10).clamp(18.0, trayWidth - 32.0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: StayFixReactionTray(
              pointerLeft: pointerLeft,
              selectedReaction: selectedReaction,
              onSelected: (reaction) => Navigator.pop(context, reaction),
            ),
          ),
        ],
      ),
    );
  }
}

class StayFixReactionTray extends StatelessWidget {
  const StayFixReactionTray({
    super.key,
    required this.pointerLeft,
    required this.selectedReaction,
    required this.onSelected,
  });

  final double pointerLeft;
  final String? selectedReaction;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCC1B2431),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _kReactionIcons.keys.map((reaction) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: StayFixReactionButton(
                      reaction: reaction,
                      selected: reaction == selectedReaction,
                      onTap: () => onSelected(reaction),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(pointerLeft, -1),
          child: CustomPaint(
            size: const Size(20, 10),
            painter: _ReactionPointerPainter(),
          ),
        ),
      ],
    );
  }
}

class StayFixReactionButton extends StatefulWidget {
  const StayFixReactionButton({
    super.key,
    required this.reaction,
    required this.selected,
    required this.onTap,
  });

  final String reaction;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<StayFixReactionButton> createState() => _StayFixReactionButtonState();
}

class _StayFixReactionButtonState extends State<StayFixReactionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = _kReactionColors[widget.reaction] ?? Colors.white;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _pressed ? 0.92 : 1,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: widget.selected ? 0.95 : 0.52),
                const Color(0xFF1F2A37),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.38),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.24),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            _kReactionIcons[widget.reaction],
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class StayFixReactionBadge extends StatelessWidget {
  const StayFixReactionBadge({
    super.key,
    required this.reaction,
    this.highlighted = false,
  });

  final String reaction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final accent = _kReactionColors[reaction] ?? kAuthGold;
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: highlighted ? 1.08 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.96),
              const Color(0xFF314B76),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          _kReactionIcons[reaction],
          color: Colors.white,
          size: 14,
        ),
      ),
    );
  }
}

class _StayFixHeartBurst extends StatelessWidget {
  const _StayFixHeartBurst();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD6A85A), Color(0xFF406ACF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD6A85A).withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        LucideIcons.heart,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

class _ReactionPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xCC1B2431),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

bool _isQualifiedLaborDepartment(String? department) {
  final normalized = (department ?? '')
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
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

String _buildGroupSubtitle(Map<String, dynamic> data) {
  final memberCount = (data['memberCount'] as num?)?.toInt();
  if (memberCount != null && memberCount > 0) {
    return 'Groupe · $memberCount membre${memberCount > 1 ? 's' : ''}';
  }
  final participants = ((data['participants'] as List?) ?? const []).length;
  if (participants > 0) {
    return 'Groupe · $participants membre${participants > 1 ? 's' : ''}';
  }
  return 'Groupe';
}

Future<void> _pickAndUploadGroupAvatar(
  BuildContext context, {
  required String conversationId,
}) async {
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
            color: _kThreadCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kThreadBorder),
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
              _AttachmentOption(
                icon: LucideIcons.image,
                title: 'Galerie',
                subtitle: 'Choisir une photo de groupe',
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 10),
              _AttachmentOption(
                icon: LucideIcons.camera,
                title: 'Camera',
                subtitle: 'Prendre une photo de groupe',
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (source == null) return;

  try {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2200,
    );
    if (picked == null) return;

    final conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId);
    final snapshot = await conversationRef.get();
    final oldFileId = (snapshot.data()?['avatarFileId'] as String?)?.trim();
    final uploaded = await VpsMediaService.uploadFile(
      file: File(picked.path),
      category: 'group-avatar',
      conversationId: conversationId,
    );
    await conversationRef.set({
      'avatarUrl': uploaded.url,
      'avatarFileId': uploaded.fileId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (oldFileId != null &&
        oldFileId.isNotEmpty &&
        oldFileId != uploaded.fileId) {
      unawaited(VpsMediaService.deleteFiles([oldFileId]));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo du groupe mise a jour.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de mettre a jour la photo du groupe.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }
}

class _ChatContactInfoScreen extends StatelessWidget {
  const _ChatContactInfoScreen({
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    Uint8List? photoBytes;
    if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        photoBytes = base64Decode(avatarBase64!);
      } catch (_) {}
    }

    final conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId);
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        AppSessionService.currentUserId;
    const heroHeight = 264.0;

    return Scaffold(
      backgroundColor: _kThreadBg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: conversationRef.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final mutedBy =
              ((data['mutedBy'] as List?) ?? const []).map((e) => '$e').toSet();
          final notificationsEnabled = !mutedBy.contains(uid);
          final isTeamConversation = (data['type'] as String?) == 'team';
          final activeAvatarUrl =
              VpsMediaService.resolveProfileImageUrl(data) ?? avatarUrl;
          final activeTitle =
              ((data['title'] as String?)?.trim().isNotEmpty ?? false)
                  ? (data['title'] as String).trim()
                  : title;
          final activeSubtitle =
              isTeamConversation ? _buildGroupSubtitle(data) : subtitle;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: heroHeight,
                backgroundColor: _kThreadBg,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/conduheroimg.webp',
                        fit: BoxFit.cover,
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x6A000000),
                              Color(0xB0000000),
                              _kThreadBg,
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 74, 24, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 94,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 82,
                                      height: 82,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color:
                                              kAuthGold.withValues(alpha: 0.52),
                                          width: 2.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.26),
                                            blurRadius: 18,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: activeAvatarUrl != null &&
                                              activeAvatarUrl.isNotEmpty
                                          ? Image.network(
                                              activeAvatarUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  photoBytes != null
                                                      ? Image.memory(
                                                          photoBytes,
                                                          fit: BoxFit.cover,
                                                        )
                                                      : _ContactInfoInitial(
                                                          title: activeTitle),
                                            )
                                          : photoBytes != null
                                              ? Image.memory(
                                                  photoBytes,
                                                  fit: BoxFit.cover,
                                                )
                                              : _ContactInfoInitial(
                                                  title: activeTitle),
                                    ),
                                    if (isTeamConversation)
                                      Positioned(
                                        right: 0,
                                        top: 28,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _pickAndUploadGroupAvatar(
                                            context,
                                            conversationId: conversationId,
                                          ),
                                          child: Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: _kThreadCard,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: kAuthGold.withValues(
                                                    alpha: 0.42),
                                              ),
                                            ),
                                            child: const Icon(
                                              LucideIcons.camera,
                                              color: kAuthGold,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                activeTitle,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                activeSubtitle,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 13,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                title: Text(
                  isTeamConversation ? 'Group info' : 'Contact info',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        _ContactInfoPanel(
                          title: isTeamConversation
                              ? 'Parametres du groupe'
                              : 'Parametres de conversation',
                          child: Column(
                            children: [
                              _ContactInfoTile(
                                icon: LucideIcons.bell,
                                title: 'Notifications',
                                subtitle: notificationsEnabled
                                    ? isTeamConversation
                                        ? 'Recevez les alertes des nouvelles activites du groupe.'
                                        : 'Restez averti quand ce contact vous ecrit.'
                                    : isTeamConversation
                                        ? 'Les notifications sont en pause pour ce groupe.'
                                        : 'Les notifications sont en pause pour cette conversation.',
                                trailing: Switch(
                                  value: notificationsEnabled,
                                  activeTrackColor: const Color(0xFF22C55E),
                                  activeThumbColor: Colors.white,
                                  onChanged: (enabled) {
                                    final op = enabled
                                        ? FieldValue.arrayRemove([uid])
                                        : FieldValue.arrayUnion([uid]);
                                    conversationRef.set({
                                      'mutedBy': op,
                                    }, SetOptions(merge: true));
                                  },
                                ),
                              ),
                              const _ContactInfoTile(
                                icon: LucideIcons.server,
                                title: 'Media storage',
                                subtitle:
                                    'Vos medias partages sont proteges par le stockage securise StayFix.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _ContactInfoPanel(
                          title: isTeamConversation
                              ? 'Actions du groupe'
                              : 'Actions',
                          child: Column(
                            children: [
                              if (isTeamConversation)
                                _ContactInfoTile(
                                  icon: LucideIcons.userPlus,
                                  title: 'Ajouter des membres',
                                  subtitle:
                                      'Ajoutez d autres membres deja connus dans vos conversations.',
                                  onTap: () async {
                                    await showModalBottomSheet<void>(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      isScrollControlled: true,
                                      builder: (_) => _AddGroupMembersSheet(
                                        conversationId: conversationId,
                                        managerUid: uid,
                                        existingParticipantIds:
                                            ((data['participants'] as List?) ??
                                                    const [])
                                                .map((e) => '$e')
                                                .toSet(),
                                      ),
                                    );
                                  },
                                ),
                              _ContactInfoTile(
                                icon: LucideIcons.trash2,
                                title: 'Clear chat',
                                subtitle: isTeamConversation
                                    ? 'Supprime l historique de ce groupe.'
                                    : 'Supprime l historique de cette conversation.',
                                destructive: true,
                                onTap: () async {
                                  await _clearConversationHistoryById(
                                    conversationId,
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            ],
                          ),
                        ),
                        if (isTeamConversation) ...[
                          const SizedBox(height: 18),
                          _ContactInfoPanel(
                            title: 'Membres',
                            child:
                                FutureBuilder<List<_ConversationMemberProfile>>(
                              future: _loadConversationMembers(data),
                              builder: (context, membersSnapshot) {
                                final members =
                                    membersSnapshot.data ?? const [];
                                if (members.isEmpty) {
                                  return Text(
                                    'Aucun membre trouve.',
                                    style: GoogleFonts.inter(
                                      color:
                                          Colors.white.withValues(alpha: 0.64),
                                    ),
                                  );
                                }
                                return Column(
                                  children: members
                                      .map(
                                        (member) => _ConversationMemberTile(
                                          member: member,
                                          canRemove: member.id != uid,
                                          onRemove: member.id == uid
                                              ? null
                                              : () async {
                                                  await _removeConversationMember(
                                                    conversationId:
                                                        conversationId,
                                                    member: member,
                                                  );
                                                },
                                        ),
                                      )
                                      .toList(),
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
          );
        },
      ),
    );
  }
}

class _ContactInfoPanel extends StatelessWidget {
  const _ContactInfoPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kThreadCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _kThreadBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: kAuthGold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ContactInfoInitial extends StatelessWidget {
  const _ContactInfoInitial({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF101010),
            Color(0xFF1B1B1B),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: kAuthGold,
          fontSize: 34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContactInfoTile extends StatelessWidget {
  const _ContactInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? const Color(0xFFFF7D7D) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: destructive
                    ? const Color(0x33FF7D7D)
                    : kAuthGold.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: destructive
                      ? const Color(0x44FF7D7D)
                      : kAuthGold.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(icon, color: titleColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _ConversationMemberProfile {
  const _ConversationMemberProfile({
    required this.id,
    required this.name,
    required this.tag,
    this.apartmentBadge,
  });

  final String id;
  final String name;
  final String tag;
  final String? apartmentBadge;
}

Future<List<_ConversationMemberProfile>> _loadConversationMembers(
  Map<String, dynamic> data,
) async {
  final participantIds = ((data['participants'] as List?) ?? const [])
      .map((e) => '$e')
      .where((e) => e.trim().isNotEmpty)
      .toList();
  final members = <_ConversationMemberProfile>[];
  for (final id in participantIds) {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
    final profileDoc =
        await FirebaseFirestore.instance.collection('profiles').doc(id).get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final profileData = profileDoc.data() ?? const <String, dynamic>{};
    final firstName = (userData['firstName'] as String?)?.trim() ?? '';
    final lastName = (userData['lastName'] as String?)?.trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final fallback = (profileData['username'] as String?)?.trim() ??
        (userData['username'] as String?)?.trim() ??
        'Membre';
    final accountType =
        (userData['accountType'] as String?)?.trim().toLowerCase() ?? '';
    final apartmentId = ((userData['apartmentId'] ??
                userData['propertyId'] ??
                userData['managedPropertyId']) as String?)
            ?.trim() ??
        '';
    String? apartmentBadge;
    if (apartmentId.isNotEmpty) {
      final apartmentDoc = await FirebaseFirestore.instance
          .collection('hotels')
          .doc(apartmentId)
          .get();
      final apartmentName = (apartmentDoc.data()?['name'] as String?)?.trim();
      if (apartmentName != null && apartmentName.isNotEmpty) {
        apartmentBadge = apartmentName;
      }
    }
    final tag = accountType == 'concierge' || accountType == 'stayfix_job'
        ? 'Concierge'
        : accountType == 'manager' || accountType == 'apartment_manager'
            ? 'Gestionnaire'
            : accountType == 'apartment_account'
                ? 'Appartement'
                : ((userData['role'] as String?)?.trim().isNotEmpty ?? false)
                    ? (userData['role'] as String).trim()
                    : 'Membre';
    members.add(
      _ConversationMemberProfile(
        id: id,
        name: fullName.isNotEmpty ? fullName : fallback,
        tag: tag,
        apartmentBadge: apartmentBadge,
      ),
    );
  }
  return members;
}

Future<void> _removeConversationMember({
  required String conversationId,
  required _ConversationMemberProfile member,
}) async {
  final conversationRef = FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId);
  final snapshot = await conversationRef.get();
  final data = snapshot.data() ?? const <String, dynamic>{};
  final participants = ((data['participants'] as List?) ?? const [])
      .map((e) => '$e')
      .where((e) => e.trim().isNotEmpty && e != member.id)
      .toList();
  final actorId =
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;
  final actorName = ((AppSessionService.currentUserData['firstName'] as String?)
                  ?.trim() ??
              '')
          .isNotEmpty
      ? '${(AppSessionService.currentUserData['firstName'] as String?)?.trim() ?? ''} ${(AppSessionService.currentUserData['lastName'] as String?)?.trim() ?? ''}'
          .trim()
      : ((AppSessionService.currentUserData['username'] as String?)?.trim() ??
          'Gestionnaire');
  final removalText = '$actorName a retire ${member.name} du groupe.';
  await conversationRef.set({
    'participants': participants,
    'memberCount': participants.length,
    'unreadBy.${member.id}': FieldValue.delete(),
    'lastReadAt.${member.id}': FieldValue.delete(),
    'lastMessage': removalText,
    'lastMessageAt': FieldValue.serverTimestamp(),
    'systemBannerText': removalText,
    'systemBannerKind': 'member_removed',
    'systemBannerAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  await conversationRef.collection('messages').add({
    'senderId': actorId,
    'messageType': 'member_removed',
    'text': removalText,
    'createdAt': FieldValue.serverTimestamp(),
    'sentAt': FieldValue.serverTimestamp(),
    'deliveredTo': actorId.isEmpty ? const <String>[] : [actorId],
    'seenBy': actorId.isEmpty ? const <String>[] : [actorId],
  });
}

class _ConversationMemberTile extends StatelessWidget {
  const _ConversationMemberTile({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  final _ConversationMemberProfile member;
  final bool canRemove;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kAuthGold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
              style: GoogleFonts.inter(
                color: kAuthGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kAuthGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    member.tag,
                    style: GoogleFonts.inter(
                      color: kAuthGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if ((member.apartmentBadge ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kThreadBorder),
                    ),
                    child: Text(
                      member.apartmentBadge!,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canRemove)
            TextButton(
              onPressed: () async => onRemove?.call(),
              child: Text(
                'Retirer',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFF7D7D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddGroupMembersSheet extends StatefulWidget {
  const _AddGroupMembersSheet({
    required this.conversationId,
    required this.managerUid,
    required this.existingParticipantIds,
  });

  final String conversationId;
  final String managerUid;
  final Set<String> existingParticipantIds;

  @override
  State<_AddGroupMembersSheet> createState() => _AddGroupMembersSheetState();
}

class _AddGroupMembersSheetState extends State<_AddGroupMembersSheet> {
  final Set<String> _selectedIds = <String>{};
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;
  bool _saving = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWorkers();
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
            .where((e) =>
                e != widget.managerUid &&
                !widget.existingParticipantIds.contains(e))
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
      if (!mounted) return;
      setState(() {
        _workers = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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

  Future<void> _addMembers() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);
      final snapshot = await ref.get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final currentParticipants = ((data['participants'] as List?) ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toSet();
      currentParticipants.addAll(_selectedIds);

      final mergedUnreadBy = <String, dynamic>{
        ...((data['unreadBy'] as Map?) ?? const {}),
      };
      final mergedLastReadAt = <String, dynamic>{
        ...((data['lastReadAt'] as Map?) ?? const {}),
      };
      for (final id in _selectedIds) {
        mergedUnreadBy[id] = mergedUnreadBy[id] ?? 0;
        mergedLastReadAt[id] = mergedLastReadAt[id];
      }

      final existingPhotos = ((data['memberPhotoBase64s'] as List?) ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final selectedPhotos = _workers
          .where((w) => _selectedIds.contains(w['id']))
          .map((w) => (w['photo'] as String?)?.trim() ?? '')
          .where((e) => e.isNotEmpty);
      final mergedPhotos = {
        ...existingPhotos,
        ...selectedPhotos,
      }.take(3).toList();
      final addedCount = _selectedIds.length;
      final actorName = _resolveCurrentActorName();
      final addedNames = _workers
          .where((w) => _selectedIds.contains(w['id']))
          .map((w) => (w['name'] as String?)?.trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      final bannerText = addedCount == 1
          ? '$actorName a ajoute ${addedNames.isNotEmpty ? addedNames.first : 'un membre'}.'
          : '$actorName a ajoute $addedCount membres au groupe.';

      await ref.set({
        'participants': currentParticipants.toList(),
        'memberCount': currentParticipants.length,
        'memberPhotoBase64s': mergedPhotos,
        'unreadBy': mergedUnreadBy,
        'lastReadAt': mergedLastReadAt,
        'lastReadAt.${widget.managerUid}': FieldValue.serverTimestamp(),
        'lastMessage': bannerText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': widget.managerUid,
        'systemBannerText': bannerText,
        'systemBannerKind': 'member_added',
        'systemBannerAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await ref.collection('messages').add({
        'senderId': widget.managerUid,
        'messageType': 'member_added',
        'text': bannerText,
        'createdAt': FieldValue.serverTimestamp(),
        'sentAt': FieldValue.serverTimestamp(),
        'deliveredTo':
            widget.managerUid.isEmpty ? const <String>[] : [widget.managerUid],
        'seenBy':
            widget.managerUid.isEmpty ? const <String>[] : [widget.managerUid],
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d ajouter ces membres pour le moment.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.80,
          ),
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
              const SizedBox(height: 18),
              Text(
                'Ajouter des membres',
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Choisissez les intervenants a ajouter a ce groupe.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
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
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kAuthGold),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun intervenant a ajouter pour le moment.',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.40),
                                fontSize: 13,
                              ),
                            ),
                          )
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
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? kAuthGold.withValues(alpha: 0.12)
                                        : const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? kAuthGold.withValues(alpha: 0.50)
                                          : Colors.white
                                              .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      _GroupMemberThumb(
                                        photo: w['photo'] as String?,
                                        name: w['name'] as String,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              w['name'] as String,
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if ((w['subtitle'] as String)
                                                .isNotEmpty)
                                              Text(
                                                w['subtitle'] as String,
                                                style: GoogleFonts.inter(
                                                  color: kAuthGold,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        selected
                                            ? LucideIcons.checkCircle
                                            : LucideIcons.circle,
                                        color: selected
                                            ? kAuthGold
                                            : Colors.white
                                                .withValues(alpha: 0.25),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_selectedIds.isNotEmpty && !_saving)
                      ? _addMembers
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAuthGold,
                    disabledBackgroundColor: kAuthGold.withValues(alpha: 0.30),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          _selectedIds.isEmpty
                              ? 'Ajouter des membres'
                              : 'Ajouter ${_selectedIds.length} membre(s)',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
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

class _GroupMemberThumb extends StatelessWidget {
  const _GroupMemberThumb({
    required this.photo,
    required this.name,
  });

  final String? photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      try {
        final bytes = base64Decode(photo!);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        );
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
            color: kAuthGold,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
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
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kThreadBorder),
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
            const SizedBox(width: 10),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.34),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatOptionTile extends StatelessWidget {
  const _ChatOptionTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFD64B4B) : Colors.black87;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailing,
    );
  }
}
