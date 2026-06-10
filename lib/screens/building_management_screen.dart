import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import '../services/app_session_service.dart';
import '../services/property_scope_service.dart';
import '../services/scoped_account_service.dart';
import '../services/stayfix_email_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BuildingManagementScreen extends StatefulWidget {
  const BuildingManagementScreen({
    super.key,
    this.autoOpenApartmentForm = false,
    this.pendingMemberAccountType,
  });

  final bool autoOpenApartmentForm;
  final String? pendingMemberAccountType;

  @override
  State<BuildingManagementScreen> createState() =>
      _BuildingManagementScreenState();
}

class _BuildingManagementScreenState extends State<BuildingManagementScreen> {
  late Future<_BuildingData> _future;
  bool _handledInitialIntent = false;

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BuildingData> _load() async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw StateError('user-not-found');
    }

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final accountType = PropertyScopeService.normalizeAccountType(userData);
    final scopedPropertyIds = PropertyScopeService.scopedPropertyIds(userData);
    final isApartmentScoped =
        PropertyScopeService.isApartmentScopedAccountType(accountType);
    final canManageBuilding = !isApartmentScoped &&
        !PropertyScopeService.isBuildingScopedAccountType(accountType);

    final apartments = await _loadApartments(
      uid: uid,
      accountType: accountType,
      scopedPropertyIds: scopedPropertyIds,
    );
    final members = await _loadMembersForApartments(apartments);

    final countsByApartment = <String, _ApartmentMemberCounts>{};
    for (final member in members) {
      final current = countsByApartment[member.apartmentId] ??
          const _ApartmentMemberCounts();
      countsByApartment[member.apartmentId] = member.accountType == 'concierge'
          ? current.copyWith(concierges: current.concierges + 1)
          : current.copyWith(managers: current.managers + 1);
    }

    return _BuildingData(
      userData: userData,
      accountType: accountType,
      apartments: apartments,
      countsByApartment: countsByApartment,
      canManageBuilding: canManageBuilding,
    );
  }

  Future<List<_ApartmentItem>> _loadApartments({
    required String uid,
    required String accountType,
    required List<String> scopedPropertyIds,
  }) async {
    final apartmentDocs = <DocumentSnapshot<Map<String, dynamic>>>[];

    if (PropertyScopeService.isApartmentScopedAccountType(accountType) ||
        PropertyScopeService.isBuildingScopedAccountType(accountType)) {
      for (final propertyId in scopedPropertyIds) {
        final doc = await FirebaseFirestore.instance
            .collection('hotels')
            .doc(propertyId)
            .get();
        if (doc.exists) {
          apartmentDocs.add(doc);
        }
      }
      if (PropertyScopeService.isApartmentScopedAccountType(accountType) &&
          apartmentDocs.isEmpty) {
        final fallbackSnapshot = await FirebaseFirestore.instance
            .collection('hotels')
            .where('accountUid', isEqualTo: uid)
            .limit(1)
            .get();
        apartmentDocs.addAll(fallbackSnapshot.docs);
      }
    } else {
      final apartmentSnapshot = await FirebaseFirestore.instance
          .collection('hotels')
          .where('ownerId', isEqualTo: uid)
          .get();
      apartmentDocs.addAll(apartmentSnapshot.docs);
    }

    final apartments = apartmentDocs
        .where((doc) =>
            ((doc.data()?['status'] as String?)?.trim().toLowerCase() ??
                'active') !=
            'deleted')
        .map(_ApartmentItem.fromDoc)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return apartments;
  }

  Future<List<_ScopedMember>> _loadMembersForApartments(
    List<_ApartmentItem> apartments,
  ) async {
    final memberDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final apartment in apartments) {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('apartmentId', isEqualTo: apartment.id)
          .get();
      memberDocs.addAll(snapshot.docs);
    }

    return memberDocs
        .where((doc) {
          final data = doc.data();
          final type = PropertyScopeService.normalizeAccountType(data);
          return (type == 'apartment_manager' || type == 'concierge') &&
              !PropertyScopeService.isDisabled(data);
        })
        .map(_ScopedMember.fromDoc)
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF111111),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleInitialIntent(_BuildingData data) async {
    if (_handledInitialIntent) return;
    _handledInitialIntent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.autoOpenApartmentForm) {
        final apartmentId = await _openAddApartmentSheet();
        if (apartmentId != null && mounted) {
          await _refresh();
          _openApartmentDetail(
            apartmentId: apartmentId,
            autoOpenMemberAccountType: widget.pendingMemberAccountType,
            canManageMembers:
                _canManageMembers(data.accountType, data.canManageBuilding),
            canDeleteApartment: data.canManageBuilding,
          );
        }
        return;
      }

      final pendingType = widget.pendingMemberAccountType;
      if (pendingType != null && pendingType.isNotEmpty) {
        await _handlePendingMemberIntent(data, pendingType);
        return;
      }

      if (!data.canManageBuilding && data.apartments.length == 1) {
        _openApartmentDetail(
          apartmentId: data.apartments.first.id,
          canManageMembers:
              _canManageMembers(data.accountType, data.canManageBuilding),
          canDeleteApartment: data.canManageBuilding,
        );
      }
    });
  }

  Future<void> _handlePendingMemberIntent(
    _BuildingData data,
    String accountType,
  ) async {
    if (data.apartments.isEmpty) {
      if (!data.canManageBuilding) {
        _showSnack('Aucun appartement n est encore lie a ce compte.');
        return;
      }
      final shouldCreateApartment = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF111111),
              title: Text(
                'Ajoutez un appartement d abord',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Text(
                'Un gestionnaire ou un concierge doit etre lie a un appartement.',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Plus tard',
                    style: GoogleFonts.inter(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAuthGold,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    'Ajouter un appartement',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!shouldCreateApartment) return;
      final apartmentId = await _openAddApartmentSheet();
      if (apartmentId == null || !mounted) return;
      await _refresh();
      _openApartmentDetail(
        apartmentId: apartmentId,
        autoOpenMemberAccountType: accountType,
        canManageMembers:
            _canManageMembers(data.accountType, data.canManageBuilding),
        canDeleteApartment: data.canManageBuilding,
      );
      return;
    }

    final apartment = await _pickApartment(data.apartments);
    if (apartment == null || !mounted) return;
    _openApartmentDetail(
      apartmentId: apartment.id,
      autoOpenMemberAccountType: accountType,
      canManageMembers:
          _canManageMembers(data.accountType, data.canManageBuilding),
      canDeleteApartment: data.canManageBuilding,
    );
  }

  Future<String?> _openAddApartmentSheet() async {
    final result = await showModalBottomSheet<_ScopedCreationResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddApartmentSheet(immeubleOwnerId: _uid),
    );
    if (result != null && mounted) {
      await _refresh();
      _showSnack(result.feedbackMessage);
    }
    return result?.apartmentId;
  }

  Future<_ApartmentItem?> _pickApartment(List<_ApartmentItem> apartments) {
    return showModalBottomSheet<_ApartmentItem>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApartmentPickerSheet(apartments: apartments),
    );
  }

  void _openApartmentDetail({
    required String apartmentId,
    String? autoOpenMemberAccountType,
    required bool canManageMembers,
    required bool canDeleteApartment,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApartmentDetailScreen(
          apartmentId: apartmentId,
          immeubleOwnerId: _uid,
          autoOpenMemberAccountType: autoOpenMemberAccountType,
          canManageMembers: canManageMembers,
          canDeleteApartment: canDeleteApartment,
        ),
      ),
    ).then((_) => _refresh());
  }

  bool _canManageMembers(String accountType, bool canManageBuilding) =>
      canManageBuilding || accountType == 'apartment_account';

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) return const AuthScreen();

    return Scaffold(
      backgroundColor: kAuthBg,
      appBar: AppBar(
        backgroundColor: kAuthBg,
        title: Text(
          'Gestion immeuble',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: FutureBuilder<_BuildingData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: kAuthGold),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data!;
          _handleInitialIntent(data);

          return RefreshIndicator(
            color: kAuthGold,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (data.canManageBuilding) ...[
                  _HeaderPanel(
                    title: 'Appartements',
                    subtitle:
                        'Ajoutez les comptes appartement puis ouvrez chaque fiche pour gerer les gestionnaires et concierges lies.',
                    primaryLabel: 'Ajouter un appartement',
                    onPrimaryTap: _openAddApartmentSheet,
                  ),
                  const SizedBox(height: 18),
                ],
                _SectionTitle(
                  title: data.canManageBuilding
                      ? 'Appartement(s)'
                      : 'Votre appartement',
                  subtitle:
                      '${data.apartments.length} compte${data.apartments.length > 1 ? 's' : ''} appartement',
                ),
                const SizedBox(height: 12),
                if (data.apartments.isEmpty)
                  _EmptyPanel(
                    icon: LucideIcons.building2,
                    title: data.canManageBuilding
                        ? 'Aucun appartement ajoute'
                        : 'Aucun appartement assigne',
                    subtitle: data.canManageBuilding
                        ? 'Commencez par creer un compte appartement. Vous pourrez ensuite ajouter ses gestionnaires et concierges depuis la fiche detail.'
                        : 'Aucun appartement n est encore lie a ce compte.',
                  )
                else
                  ...data.apartments.map(
                    (apartment) {
                      final counts = data.countsByApartment[apartment.id] ??
                          const _ApartmentMemberCounts();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ApartmentCard(
                          apartment: apartment,
                          counts: counts,
                          onOpen: () => _openApartmentDetail(
                            apartmentId: apartment.id,
                            canManageMembers: _canManageMembers(
                              data.accountType,
                              data.canManageBuilding,
                            ),
                            canDeleteApartment: data.canManageBuilding,
                          ),
                        ),
                      );
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

class ApartmentDetailScreen extends StatefulWidget {
  const ApartmentDetailScreen({
    super.key,
    required this.apartmentId,
    required this.immeubleOwnerId,
    this.autoOpenMemberAccountType,
    required this.canManageMembers,
    required this.canDeleteApartment,
  });

  final String apartmentId;
  final String immeubleOwnerId;
  final String? autoOpenMemberAccountType;
  final bool canManageMembers;
  final bool canDeleteApartment;

  @override
  State<ApartmentDetailScreen> createState() => _ApartmentDetailScreenState();
}

class _ApartmentDetailScreenState extends State<ApartmentDetailScreen> {
  late Future<_ApartmentDetailData> _future;
  bool _handledInitialIntent = false;

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionService.currentUserId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ApartmentDetailData> _load() async {
    final apartmentDoc = await FirebaseFirestore.instance
        .collection('hotels')
        .doc(widget.apartmentId)
        .get();
    if (!apartmentDoc.exists) {
      throw StateError('apartment-not-found');
    }

    final apartment = _ApartmentItem.fromDoc(apartmentDoc);
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('apartmentId', isEqualTo: widget.apartmentId)
        .get();
    final members = usersSnapshot.docs
        .where((doc) {
          final data = doc.data();
          final type = PropertyScopeService.normalizeAccountType(data);
          return (type == 'apartment_manager' || type == 'concierge') &&
              !PropertyScopeService.isDisabled(data);
        })
        .map(_ScopedMember.fromDoc)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return _ApartmentDetailData(
      apartment: apartment,
      managers: members
          .where((member) => member.accountType == 'apartment_manager')
          .toList(),
      concierges:
          members.where((member) => member.accountType == 'concierge').toList(),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF111111),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleInitialIntent(_ApartmentDetailData data) async {
    if (_handledInitialIntent) return;
    _handledInitialIntent = true;
    final accountType = widget.autoOpenMemberAccountType;
    if (accountType == null || accountType.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openAddMemberSheet(data.apartment, accountType);
    });
  }

  Future<void> _openAddMemberSheet(
    _ApartmentItem apartment,
    String accountType,
  ) async {
    final result = await showModalBottomSheet<_ScopedCreationResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddScopedMemberSheet(
        apartment: apartment,
        immeubleOwnerId: widget.immeubleOwnerId,
        accountType: accountType,
      ),
    );
    if (result != null) {
      await _refresh();
      if (mounted) {
        _showSnack(result.feedbackMessage);
      }
    }
  }

  Future<void> _deleteMember(_ScopedMember member) async {
    await ScopedAccountService.deleteScopedUserDocuments(member.uid);
    if (!mounted) return;
    _showSnack(
      member.accountType == 'concierge'
          ? 'Concierge supprime.'
          : 'Gestionnaire supprime.',
    );
    await _refresh();
  }

  Future<void> _deleteApartment(_ApartmentDetailData data) async {
    if (data.managers.isNotEmpty || data.concierges.isNotEmpty) {
      _showSnack(
        'Supprimez d abord les gestionnaires et concierges lies a cet appartement.',
      );
      return;
    }
    if (data.apartment.accountUid.isEmpty) {
      _showSnack('Impossible de supprimer cet appartement pour le moment.');
      return;
    }
    await ScopedAccountService.archiveApartment(
      apartmentId: data.apartment.id,
      apartmentAccountUid: data.apartment.accountUid,
    );
    if (!mounted) return;
    _showSnack('Appartement archive.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthBg,
      appBar: AppBar(
        backgroundColor: kAuthBg,
        title: Text(
          'Detail appartement',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: FutureBuilder<_ApartmentDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: kAuthGold),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data!;
          _handleInitialIntent(data);

          return RefreshIndicator(
            color: kAuthGold,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ApartmentInfoPanel(apartment: data.apartment),
                const SizedBox(height: 16),
                if (widget.canManageMembers) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _CompactActionButton(
                        label: 'Ajouter un gestionnaire',
                        icon: LucideIcons.userPlus,
                        onTap: () => _openAddMemberSheet(
                          data.apartment,
                          'apartment_manager',
                        ),
                      ),
                      _CompactActionButton(
                        label: 'Ajouter un concierge',
                        icon: LucideIcons.conciergeBell,
                        onTap: () => _openAddMemberSheet(
                          data.apartment,
                          'concierge',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                _SectionTitle(
                  title: 'Gestionnaires lies',
                  subtitle: '${data.managers.length} compte(s)',
                ),
                const SizedBox(height: 12),
                if (data.managers.isEmpty)
                  const _EmptyPanel(
                    icon: LucideIcons.userPlus,
                    title: 'Aucun gestionnaire',
                    subtitle:
                        'Ajoutez un gestionnaire scoped a cet appartement.',
                  )
                else
                  ...data.managers.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberCard(
                        member: member,
                        isCurrentUser: member.uid == _currentUid,
                        onDelete:
                            widget.canManageMembers && member.uid != _currentUid
                                ? () => _deleteMember(member)
                                : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'Concierges lies',
                  subtitle: '${data.concierges.length} compte(s)',
                ),
                const SizedBox(height: 12),
                if (data.concierges.isEmpty)
                  const _EmptyPanel(
                    icon: LucideIcons.conciergeBell,
                    title: 'Aucun concierge',
                    subtitle:
                        'Les concierges restent des comptes StayFix Job lies a cet appartement.',
                  )
                else
                  ...data.concierges.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberCard(
                        member: member,
                        isCurrentUser: member.uid == _currentUid,
                        onDelete:
                            widget.canManageMembers && member.uid != _currentUid
                                ? () => _deleteMember(member)
                                : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (widget.canDeleteApartment)
                  OutlinedButton.icon(
                    onPressed: () => _deleteApartment(data),
                    icon: const Icon(LucideIcons.trash2),
                    label: Text(
                      'Supprimer cet appartement',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF7B7B),
                      side: const BorderSide(color: Color(0x44FF7B7B)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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

class _BuildingData {
  const _BuildingData({
    required this.userData,
    required this.accountType,
    required this.apartments,
    required this.countsByApartment,
    required this.canManageBuilding,
  });

  final Map<String, dynamic> userData;
  final String accountType;
  final List<_ApartmentItem> apartments;
  final Map<String, _ApartmentMemberCounts> countsByApartment;
  final bool canManageBuilding;
}

class _ApartmentDetailData {
  const _ApartmentDetailData({
    required this.apartment,
    required this.managers,
    required this.concierges,
  });

  final _ApartmentItem apartment;
  final List<_ScopedMember> managers;
  final List<_ScopedMember> concierges;
}

class _ApartmentItem {
  const _ApartmentItem({
    required this.id,
    required this.name,
    required this.email,
    required this.accountUid,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String accountUid;
  final String status;
  final DateTime? createdAt;

  factory _ApartmentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return _ApartmentItem(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : 'Appartement',
      email: (data['email'] as String?)?.trim() ?? '',
      accountUid: (data['accountUid'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class _ScopedMember {
  const _ScopedMember({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.accountType,
    required this.apartmentId,
    required this.apartmentName,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String accountType;
  final String apartmentId;
  final String apartmentName;
  final DateTime? createdAt;

  factory _ScopedMember.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final displayName =
        (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : [
                (data['firstName'] as String?)?.trim() ?? '',
                (data['lastName'] as String?)?.trim() ?? '',
              ].where((value) => value.isNotEmpty).join(' ');
    return _ScopedMember(
      uid: doc.id,
      displayName: displayName.isEmpty ? 'Compte' : displayName,
      email: (data['email'] as String?)?.trim() ?? '',
      accountType: PropertyScopeService.normalizeAccountType(data),
      apartmentId: (data['apartmentId'] as String?)?.trim() ?? '',
      apartmentName: (data['apartmentName'] as String?)?.trim() ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class _ApartmentMemberCounts {
  const _ApartmentMemberCounts({
    this.managers = 0,
    this.concierges = 0,
  });

  final int managers;
  final int concierges;

  _ApartmentMemberCounts copyWith({
    int? managers,
    int? concierges,
  }) {
    return _ApartmentMemberCounts(
      managers: managers ?? this.managers,
      concierges: concierges ?? this.concierges,
    );
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final Future<String?> Function() onPrimaryTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33D6A85A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.68),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => onPrimaryTap(),
              icon: const Icon(LucideIcons.plus),
              label: Text(
                primaryLabel,
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAuthGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApartmentCard extends StatelessWidget {
  const _ApartmentCard({
    required this.apartment,
    required this.counts,
    required this.onOpen,
  });

  final _ApartmentItem apartment;
  final _ApartmentMemberCounts counts;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x33D6A85A)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: kAuthGold.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.building2,
                color: kAuthGold,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    apartment.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    apartment.email,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniBadge(
                        icon: LucideIcons.userPlus,
                        label: '${counts.managers} gestionnaire(s)',
                      ),
                      _MiniBadge(
                        icon: LucideIcons.conciergeBell,
                        label: '${counts.concierges} concierge(s)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
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

class _ApartmentInfoPanel extends StatelessWidget {
  const _ApartmentInfoPanel({required this.apartment});

  final _ApartmentItem apartment;

  @override
  Widget build(BuildContext context) {
    final createdAtLabel = apartment.createdAt == null
        ? 'Non disponible'
        : '${apartment.createdAt!.day.toString().padLeft(2, '0')}/${apartment.createdAt!.month.toString().padLeft(2, '0')}/${apartment.createdAt!.year}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33D6A85A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            apartment.name,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _DetailLine(icon: LucideIcons.mail, label: apartment.email),
          const SizedBox(height: 8),
          _DetailLine(
            icon: LucideIcons.calendarDays,
            label: 'Creation: $createdAtLabel',
          ),
          const SizedBox(height: 8),
          _DetailLine(
            icon: LucideIcons.badgeCheck,
            label: 'Statut: ${apartment.status}',
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    this.isCurrentUser = false,
    this.onDelete,
  });

  final _ScopedMember member;
  final bool isCurrentUser;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isConcierge = member.accountType == 'concierge';
    final createdAtLabel = member.createdAt == null
        ? null
        : '${member.createdAt!.day.toString().padLeft(2, '0')}/${member.createdAt!.month.toString().padLeft(2, '0')}/${member.createdAt!.year}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33D6A85A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.displayName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kAuthGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isConcierge ? 'Concierge' : 'Gestionnaire',
                  style: GoogleFonts.inter(
                    color: kAuthGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isCurrentUser) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'C est vous',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            member.email,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          if (createdAtLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              'Cree le $createdAtLabel',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.54),
                fontSize: 12,
              ),
            ),
          ],
          if (onDelete != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(
                  LucideIcons.trash2,
                  color: Color(0xFFFF7B7B),
                  size: 16,
                ),
                label: Text(
                  'Supprimer',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFF7B7B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width =
        ((MediaQuery.sizeOf(context).width - 42) / 2).clamp(140.0, 220.0);
    return SizedBox(
      width: width,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          side: const BorderSide(color: Color(0x33D6A85A)),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _AddApartmentSheet extends StatefulWidget {
  const _AddApartmentSheet({required this.immeubleOwnerId});

  final String immeubleOwnerId;

  @override
  State<_AddApartmentSheet> createState() => _AddApartmentSheetState();
}

class _AddApartmentSheetState extends State<_AddApartmentSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final apartmentName = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    try {
      final apartmentId = await ScopedAccountService.createApartmentAccount(
        immeubleOwnerId: widget.immeubleOwnerId,
        apartmentName: apartmentName,
        email: email,
        password: password,
      );
      final emailResult = await StayfixEmailService.sendApartmentCreatedEmail(
        to: email,
        recipientName: apartmentName,
        apartmentName: apartmentName,
        loginEmail: email,
        temporaryPassword: password,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _ScopedCreationResult(
          apartmentId: apartmentId,
          emailSent: emailResult.success,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _firebaseErrorText(error),
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Ajouter un appartement',
      child: Column(
        children: [
          _Input(label: 'Nom de l appartement', controller: _nameCtrl),
          const SizedBox(height: 10),
          _Input(label: 'Email', controller: _emailCtrl),
          const SizedBox(height: 10),
          _Input(
            label: 'Mot de passe',
            controller: _passwordCtrl,
            obscureText: true,
          ),
          const SizedBox(height: 16),
          _PrimarySheetButton(
            label: _saving ? 'Creation...' : 'Creer le compte appartement',
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _AddScopedMemberSheet extends StatefulWidget {
  const _AddScopedMemberSheet({
    required this.apartment,
    required this.immeubleOwnerId,
    required this.accountType,
  });

  final _ApartmentItem apartment;
  final String immeubleOwnerId;
  final String accountType;

  @override
  State<_AddScopedMemberSheet> createState() => _AddScopedMemberSheetState();
}

class _AddScopedMemberSheetState extends State<_AddScopedMemberSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final fullName = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    try {
      if (widget.accountType == 'concierge') {
        await ScopedAccountService.createConciergeAccount(
          immeubleOwnerId: widget.immeubleOwnerId,
          apartmentId: widget.apartment.id,
          apartmentName: widget.apartment.name,
          fullName: fullName,
          email: email,
          password: password,
        );
      } else {
        await ScopedAccountService.createApartmentManagerAccount(
          immeubleOwnerId: widget.immeubleOwnerId,
          apartmentId: widget.apartment.id,
          apartmentName: widget.apartment.name,
          fullName: fullName,
          email: email,
          password: password,
        );
      }
      final recipientName = fullName.isNotEmpty ? fullName : email;
      final emailResult = widget.accountType == 'concierge'
          ? await StayfixEmailService.sendConciergeCreatedEmail(
              to: email,
              recipientName: recipientName,
              apartmentName: widget.apartment.name,
              loginEmail: email,
              temporaryPassword: password,
            )
          : await StayfixEmailService.sendManagerCreatedEmail(
              to: email,
              recipientName: recipientName,
              apartmentName: widget.apartment.name,
              loginEmail: email,
              temporaryPassword: password,
            );
      if (!mounted) return;
      Navigator.pop(
        context,
        _ScopedCreationResult(
          apartmentId: widget.apartment.id,
          emailSent: emailResult.success,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _firebaseErrorText(error),
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.accountType == 'concierge'
        ? 'Ajouter un concierge'
        : 'Ajouter un gestionnaire';
    return _SheetScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appartement: ${widget.apartment.name}',
            style: GoogleFonts.inter(
              color: kAuthGold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _Input(label: 'Nom complet', controller: _nameCtrl),
          const SizedBox(height: 10),
          _Input(label: 'Email', controller: _emailCtrl),
          const SizedBox(height: 10),
          _Input(
            label: 'Mot de passe',
            controller: _passwordCtrl,
            obscureText: true,
          ),
          const SizedBox(height: 16),
          _PrimarySheetButton(
            label: _saving ? 'Creation...' : 'Creer le compte',
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _ApartmentPickerSheet extends StatelessWidget {
  const _ApartmentPickerSheet({required this.apartments});

  final List<_ApartmentItem> apartments;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Choisir un appartement',
      child: Column(
        children: apartments
            .map(
              (apartment) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  LucideIcons.building2,
                  color: kAuthGold,
                ),
                title: Text(
                  apartment.name,
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                subtitle: Text(
                  apartment.email,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                onTap: () => Navigator.pop(context, apartment),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SingleChildScrollView(
            child: Column(
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
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.controller,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF171717),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x33D6A85A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x33D6A85A)),
        ),
      ),
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  const _PrimarySheetButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAuthGold,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.58),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kAuthGold, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kAuthGold, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33D6A85A)),
      ),
      child: Column(
        children: [
          Icon(icon, color: kAuthGold, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.64),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertTriangle, color: kAuthGold),
            const SizedBox(height: 12),
            Text(
              'Impossible de charger la gestion immeuble pour le moment.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onRetry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: kAuthGold,
                side: const BorderSide(color: kAuthGold),
              ),
              child: Text(
                'Reessayer',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _firebaseErrorText(FirebaseAuthException error) {
  switch (error.code) {
    case 'email-already-in-use':
      return 'Cette adresse email est deja utilisee.';
    case 'invalid-email':
      return 'Adresse email invalide.';
    case 'weak-password':
      return 'Le mot de passe est trop faible.';
    default:
      return 'Impossible de creer ce compte pour le moment.';
  }
}

class _ScopedCreationResult {
  const _ScopedCreationResult({
    required this.apartmentId,
    required this.emailSent,
  });

  final String apartmentId;
  final bool emailSent;

  String get feedbackMessage {
    return emailSent
        ? 'Compte cree et email envoye.'
        : 'Compte cree, mais l email n a pas pu etre envoye.';
  }
}
