import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:stayfix/screens/auth_screen.dart';
import 'package:stayfix/screens/manager_property_route_helper.dart';
import 'package:stayfix/services/property_scope_service.dart';
import 'package:stayfix/services/vps_media_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

// -- Color constants -----------------------------------------------------------
const _kBg = Color(0xFF070707);
const _kCard = Color(0xFF111111);
const _kBorder = Color(0x33D6A85A);
const _kField = Color(0xFF181818);

// -- Departments & specialties -------------------------------------------------
const _kDepartments = [
  'Propose au menage',
  'Maintenance generale',
  "Main-d'oeuvre qualifiee",
];

const _kSpecialties = <String, List<String>>{
  'Propose au menage': [
    'Entretien menager',
    'Nettoyage des espaces communs',
    'Gestion du linge',
    'Preparation des appartements',
  ],
  'Maintenance generale': [
    'Bricolage',
    'Aide generale',
    'Jardinage / Jardinage paysager',
    'Peinture generale',
  ],
  "Main-d'oeuvre qualifiee": [
    'Plomberie professionnelle',
    'Electricite avancee',
    'Climatisation & chauffage',
    'Maconnerie professionnelle',
    'Menuiserie generale / Menuiserie',
    'Peinture decorative / Peinture professionnelle',
    'Soudure industrielle',
  ],
};

const _kDurations = [
  "Moins d'1 heure",
  '1-2 heures',
  '2-4 heures',
  'Demi-journée',
  'Journée complète',
  'À déterminer',
];

const _kUrgencies = ['Faible', 'Normale', 'Urgente', 'Très urgente'];

// -- Main screen ---------------------------------------------------------------
class CreateManagerOfferScreen extends StatefulWidget {
  const CreateManagerOfferScreen({super.key, required this.uid});
  final String uid;

  @override
  State<CreateManagerOfferScreen> createState() =>
      _CreateManagerOfferScreenState();
}

class _CreateManagerOfferScreenState extends State<CreateManagerOfferScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  // Condo
  String? _condoId;
  String? _condoName;
  String? _condoAddress;
  bool _condoLoading = true;

  // Controllers
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();

  // Selections
  String? _department;
  String? _specialty;
  DateTime? _requestedDate;
  TimeOfDay? _requestedTime;
  String? _estimatedDuration;
  String _urgency = 'Normale';
  bool _isNegotiable = false;
  bool _loading = false;
  final List<_PendingOfferPhoto> _pendingPhotos = <_PendingOfferPhoto>[];
  _PendingOfferDocument? _pendingDocument;

  @override
  void initState() {
    super.initState();
    _loadCondo();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCondo() async {
    final uid = widget.uid.isNotEmpty
        ? widget.uid
        : FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      if (mounted) setState(() => _condoLoading = false);
      return;
    }
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final accountType = PropertyScopeService.normalizeAccountType(userData);
      final scopedPropertyIds = PropertyScopeService.scopedPropertyIds(userData);

      DocumentSnapshot<Map<String, dynamic>>? propertyDoc;
      if (accountType == 'apartment_account' && scopedPropertyIds.isEmpty) {
        final byAccount = await FirebaseFirestore.instance
            .collection('hotels')
            .where('accountUid', isEqualTo: uid)
            .limit(1)
            .get();
        if (byAccount.docs.isNotEmpty) {
          propertyDoc = byAccount.docs.first;
        }
      } else if (scopedPropertyIds.isNotEmpty) {
        for (final propertyId in scopedPropertyIds) {
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
        final snap = await FirebaseFirestore.instance
            .collection('hotels')
            .where('ownerId', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          propertyDoc = snap.docs.first;
        }
      }

      if (propertyDoc != null && mounted) {
        final d = propertyDoc.data() ?? const <String, dynamic>{};
        setState(() {
          _condoId = propertyDoc!.id;
          _condoName = (d['name'] as String?)?.trim();
          _condoAddress = (d['location'] as String?)?.trim();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _condoLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSoon(String msg) {
    if (msg.contains('photos')) {
      unawaited(_pickPhotos());
      return;
    }
    if (msg.contains('documents')) {
      unawaited(_pickDocument());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: const Color(0xFF1A1A1A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _requestedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kAuthGold,
            onSurface: Colors.white,
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _requestedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _requestedTime ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kAuthGold,
            onSurface: Colors.white,
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _requestedTime = picked);
  }

  Future<void> _pickFromSheet(String title, List<String> options,
      String? current, void Function(String) onSelect) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        title: title,
        options: options,
        selected: current,
        onSelect: (v) {
          Navigator.pop(context);
          onSelect(v);
        },
      ),
    );
  }

  void _openInstructions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InstructionsSheet(ctrl: _instructionsCtrl),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 82);
      if (files.isEmpty || !mounted) return;
      setState(() {
        _pendingPhotos.addAll(
          files.map((file) => _PendingOfferPhoto(file: File(file.path))),
        );
      });
    } catch (_) {
      _showError('Impossible d ajouter des photos pour le moment.');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx'],
      );
      final picked = result?.files.single;
      final path = picked?.path;
      if (picked == null || path == null || path.trim().isEmpty || !mounted) {
        return;
      }
      final extension = (picked.extension ?? '').toLowerCase().trim();
      if (extension != 'pdf' && extension != 'docx') {
        _showError('Veuillez choisir uniquement un fichier PDF ou DOCX.');
        return;
      }
      setState(() {
        _pendingDocument = _PendingOfferDocument(
          file: File(path),
          name: picked.name,
          extension: extension,
        );
      });
    } catch (_) {
      _showError('Impossible d ajouter ce document pour le moment.');
    }
  }

  Future<void> _publish() async {
    // Validation
    if (_condoId == null) {
      _showError('Veuillez ajouter votre condo avant de publier une offre.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('Veuillez saisir un titre.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError('Veuillez décrire le travail à effectuer.');
      return;
    }
    if (_department == null) {
      _showError('Veuillez sélectionner un département.');
      return;
    }
    if (_specialty == null) {
      _showError('Veuillez sélectionner une spécialité.');
      return;
    }
    if (_requestedDate == null) {
      _showError('Veuillez choisir une date.');
      return;
    }
    if (_requestedTime == null) {
      _showError('Veuillez choisir une heure.');
      return;
    }
    if (!_isNegotiable) {
      final budgetText = _budgetCtrl.text.trim();
      if (budgetText.isEmpty || double.tryParse(budgetText) == null) {
        _showError('Veuillez indiquer un budget ou activer Négociable.');
        return;
      }
    }

    setState(() => _loading = true);
    final uploadedFileIds = <String>[];
    try {
      final uid = widget.uid.isNotEmpty
          ? widget.uid
          : FirebaseAuth.instance.currentUser?.uid ?? '';
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final accountType = PropertyScopeService.normalizeAccountType(userData);
      final timeStr = _formatTime(_requestedTime!);
      final uploadedPhotos = <Map<String, dynamic>>[];
      for (final photo in _pendingPhotos) {
        final uploaded = await VpsMediaService.uploadFile(
          file: photo.file,
          category: 'offer-photo',
        );
        uploadedPhotos.add(<String, dynamic>{
          'url': uploaded.url,
          'fileId': uploaded.fileId,
          'mimeType': uploaded.mimeType,
          'sizeBytes': uploaded.sizeBytes,
          'width': uploaded.width,
          'height': uploaded.height,
          'name': photo.file.path.split(Platform.pathSeparator).last,
        });
        if (uploaded.fileId.isNotEmpty) {
          uploadedFileIds.add(uploaded.fileId);
        }
      }
      Map<String, dynamic>? uploadedDocument;
      if (_pendingDocument != null) {
        final uploaded = await VpsMediaService.uploadFile(
          file: _pendingDocument!.file,
          category: 'offer-document',
        );
        uploadedDocument = <String, dynamic>{
          'url': uploaded.url,
          'fileId': uploaded.fileId,
          'mimeType': uploaded.mimeType,
          'sizeBytes': uploaded.sizeBytes,
          'name': _pendingDocument!.name,
          'extension': _pendingDocument!.extension,
        };
        if (uploaded.fileId.isNotEmpty) {
          uploadedFileIds.add(uploaded.fileId);
        }
      }
      await FirebaseFirestore.instance.collection('offers').add({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'department': _department,
        'specialty': _specialty,
        'category': _specialty,
        'status': 'open',
        'targetApp': 'stayfix_job',
        'createdByUid': uid,
        'createdByManagerId': uid,
        'createdByRole': accountType.isEmpty ? 'manager' : accountType,
        'condoId': _condoId,
        'condoName': _condoName ?? '',
        'apartmentId': _condoId,
        'apartmentName': _condoName ?? '',
        'condoAddress': _condoAddress ?? '',
        'requestedDate': Timestamp.fromDate(_requestedDate!),
        'requestedTime': timeStr,
        'estimatedDuration': _estimatedDuration,
        'urgency': _urgency,
        'budgetAmount':
            _isNegotiable ? null : double.tryParse(_budgetCtrl.text.trim()),
        'budgetCurrency': 'DZD',
        'isNegotiable': _isNegotiable,
        'specialInstructions': _instructionsCtrl.text.trim(),
        'proposalCount': 0,
        'assignedToId': null,
        'assignedWorkerId': null,
        'assignedWorkerName': null,
        'attachments': uploadedDocument == null
            ? <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[uploadedDocument],
        'document': uploadedDocument,
        'photos': uploadedPhotos,
        'offerFileIds': uploadedFileIds,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Offre publiée avec succès',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (uploadedFileIds.isNotEmpty) {
        try {
          await VpsMediaService.deleteFiles(uploadedFileIds);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _loading = false);
        _showError('Erreur lors de la publication. Réessayez.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _CreateOfferHeader(
            onBack: () => Navigator.pop(context),
            onSaveDraft: () => _showSoon('Brouillon bientôt disponible.'),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Condo banner
                  _CondoBanner(
                    condoName: _condoName,
                    condoAddress: _condoAddress,
                    loading: _condoLoading,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => buildManagerProfileScreen(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle('Informations générales'),

                  // Title
                  _FieldCard(
                    icon: LucideIcons.fileText,
                    label: "Titre de l'offre *",
                    placeholder:
                        "Ex: Réparation fuite d'eau dans la salle de bain",
                    controller: _titleCtrl,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  _TextAreaCard(controller: _descCtrl),

                  const SizedBox(height: 24),
                  const _SectionTitle('Catégorie & spécialité'),

                  // Department
                  _DropdownCard(
                    icon: LucideIcons.briefcase,
                    label: 'Département *',
                    value: _department,
                    placeholder: 'Sélectionner un département',
                    enabled: true,
                    onTap: () => _pickFromSheet(
                      'Département',
                      _kDepartments,
                      _department,
                      (v) => setState(() {
                        _department = v;
                        _specialty = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Specialty
                  _DropdownCard(
                    icon: LucideIcons.settings2,
                    label: 'Spécialité *',
                    value: _specialty,
                    placeholder: 'Sélectionner une spécialité',
                    enabled: _department != null,
                    onTap: _department == null
                        ? null
                        : () => _pickFromSheet(
                              'Spécialité',
                              _kSpecialties[_department!] ?? [],
                              _specialty,
                              (v) => setState(() => _specialty = v),
                            ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle("Détails de l'intervention"),

                  // Date + Time
                  Row(
                    children: [
                      Expanded(
                        child: _DateCard(
                          date: _requestedDate,
                          onTap: _pickDate,
                          formatDate: _formatDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeCard(
                          time: _requestedTime,
                          onTap: _pickTime,
                          formatTime: _formatTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Duration + Urgency
                  Row(
                    children: [
                      Expanded(
                        child: _DropdownCard(
                          icon: LucideIcons.clock,
                          label: 'Durée estimée',
                          value: _estimatedDuration,
                          placeholder: 'Sélectionner',
                          enabled: true,
                          onTap: () => _pickFromSheet(
                            'Durée estimée',
                            _kDurations,
                            _estimatedDuration,
                            (v) => setState(() => _estimatedDuration = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DropdownCard(
                          icon: LucideIcons.flag,
                          label: 'Urgence',
                          value: _urgency,
                          placeholder: 'Normale',
                          enabled: true,
                          onTap: () => _pickFromSheet(
                            'Urgence',
                            _kUrgencies,
                            _urgency,
                            (v) => setState(() => _urgency = v),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle('Budget'),

                  _BudgetCard(
                    controller: _budgetCtrl,
                    isNegotiable: _isNegotiable,
                    onToggle: (v) => setState(() => _isNegotiable = v),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(
                      'Informations complémentaires (optionnel)'),

                  Row(
                    children: [
                      Expanded(
                        child: _OptionalCard(
                          icon: LucideIcons.image,
                          label: 'Ajouter des photos',
                          onTap: () =>
                              _showSoon('Ajout de photos bientôt disponible.'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionalCard(
                          icon: LucideIcons.fileText,
                          label: 'Ajouter un document',
                          onTap: () => _showSoon(
                              'Ajout de documents bientôt disponible.'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionalCard(
                          icon: LucideIcons.messageSquare,
                          label: 'Instructions spéciales',
                          onTap: _openInstructions,
                          hasContent: _instructionsCtrl.text.isNotEmpty,
                        ),
                      ),
                    ],
                  ),

                  if (_pendingPhotos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _SelectedOfferPhotos(
                      photos: _pendingPhotos,
                      onRemoveAt: (index) =>
                          setState(() => _pendingPhotos.removeAt(index)),
                    ),
                  ],
                  if (_pendingDocument != null) ...[
                    const SizedBox(height: 12),
                    _SelectedOfferDocument(
                      document: _pendingDocument!,
                      onRemove: () => setState(() => _pendingDocument = null),
                    ),
                  ],
                  const SizedBox(height: 32),
                  _PublishButton(loading: _loading, onTap: _publish),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Header --------------------------------------------------------------------
class _PendingOfferPhoto {
  const _PendingOfferPhoto({
    required this.file,
  });

  final File file;
}

class _PendingOfferDocument {
  const _PendingOfferDocument({
    required this.file,
    required this.name,
    required this.extension,
  });

  final File file;
  final String name;
  final String extension;
}

class _CreateOfferHeader extends StatelessWidget {
  const _CreateOfferHeader({
    required this.onBack,
    required this.onSaveDraft,
  });

  final VoidCallback onBack;
  final VoidCallback onSaveDraft;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            // Back
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBorder),
                ),
                child: const Icon(LucideIcons.arrowLeft,
                    color: Colors.white, size: 20),
              ),
            ),
            // Title
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Créer une offre',
                    style: GoogleFonts.cormorantGaramond(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Décrivez le travail à effectuer et recevez\ndes propositions d\'intervenants qualifiés.',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Save draft
            GestureDetector(
              onTap: onSaveDraft,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBorder),
                ),
                child: const Icon(LucideIcons.save, color: kAuthGold, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Condo Banner --------------------------------------------------------------
class _CondoBanner extends StatelessWidget {
  const _CondoBanner({
    required this.condoName,
    required this.condoAddress,
    required this.loading,
    required this.onTap,
  });

  final String? condoName;
  final String? condoAddress;
  final bool loading;
  final VoidCallback onTap;

  bool get _hasCondo => condoName != null && condoName!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: kAuthGold.withValues(alpha: 0.60),
            ),
          ),
        ),
      );
    }

    if (_hasCondo) {
      // Has condo — show name + address
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  shape: BoxShape.circle,
                  border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
                ),
                child: const Icon(LucideIcons.building2,
                    color: kAuthGold, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      condoName!,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (condoAddress != null && condoAddress!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        condoAddress!,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                'Modifier',
                style: GoogleFonts.inter(
                  color: kAuthGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight,
                  color: Colors.white.withValues(alpha: 0.30), size: 16),
            ],
          ),
        ),
      );
    }

    // No condo — show "Ajoutez votre condo"
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAuthGold),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(color: kAuthGold.withValues(alpha: 0.30)),
            ),
            child:
                const Icon(LucideIcons.building2, color: kAuthGold, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajoutez votre condo pour publier une offre',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La localisation aide les intervenants à vous trouver.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kAuthGold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ajouter votre condo',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronRight,
                      color: Colors.black, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Section Title -------------------------------------------------------------
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// -- Single-line Field Card ----------------------------------------------------
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.label,
    required this.placeholder,
    required this.controller,
  });

  final IconData icon;
  final String label;
  final String placeholder;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: kAuthGold, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
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

// -- Text Area Card (description) ----------------------------------------------
class _TextAreaCard extends StatefulWidget {
  const _TextAreaCard({required this.controller});
  final TextEditingController controller;

  @override
  State<_TextAreaCard> createState() => _TextAreaCardState();
}

class _TextAreaCardState extends State<_TextAreaCard> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.alignLeft, color: kAuthGold, size: 18),
              const SizedBox(width: 12),
              Text(
                'Description du travail *',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.controller,
            maxLines: 5,
            maxLength: 500,
            buildCounter: (_,
                    {required currentLength, maxLength, required isFocused}) =>
                null,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            inputFormatters: [LengthLimitingTextInputFormatter(500)],
            decoration: InputDecoration(
              hintText:
                  "Décrivez en détail le travail à effectuer, les tâches, les attentes...",
              hintStyle: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.30),
                fontSize: 13,
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${widget.controller.text.length}/500',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Dropdown Field Card -------------------------------------------------------
class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: _kField,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? _kBorder : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: enabled
                      ? kAuthGold
                      : Colors.white.withValues(alpha: 0.30),
                  size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value ?? placeholder,
                      style: GoogleFonts.inter(
                        color: value != null
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                color:
                    enabled ? kAuthGold : Colors.white.withValues(alpha: 0.25),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Date Card -----------------------------------------------------------------
class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.date,
    required this.onTap,
    required this.formatDate,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: _kField,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.calendar, color: kAuthGold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Date souhaitée *',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    date != null ? formatDate(date!) : 'Choisir une date',
                    style: GoogleFonts.inter(
                      color: date != null
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.calendar, color: kAuthGold, size: 14),
          ],
        ),
      ),
    );
  }
}

// -- Time Card -----------------------------------------------------------------
class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.time,
    required this.onTap,
    required this.formatTime,
  });

  final TimeOfDay? time;
  final VoidCallback onTap;
  final String Function(TimeOfDay) formatTime;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: _kField,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.clock, color: kAuthGold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Heure souhaitée *',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    time != null ? formatTime(time!) : 'Choisir une heure',
                    style: GoogleFonts.inter(
                      color: time != null
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronDown, color: kAuthGold, size: 14),
          ],
        ),
      ),
    );
  }
}

// -- Budget Card ---------------------------------------------------------------
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.controller,
    required this.isNegotiable,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool isNegotiable;
  final void Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(LucideIcons.dollarSign, color: kAuthGold, size: 18),
              const SizedBox(width: 10),
              Text(
                'Budget proposé',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Négociable',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: isNegotiable,
                onChanged: onToggle,
                activeTrackColor: const Color(0xFF22C55E),
                inactiveTrackColor: Colors.white24,
                activeThumbColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Amount row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.30),
                        fontSize: 16,
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Text(
                  '\$',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (isNegotiable) ...[
            const SizedBox(height: 10),
            Text(
              "Laissez le vide ou activez Négociable si le prix est à discuter avec l'intervenant.",
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -- Optional Action Card ------------------------------------------------------
class _OptionalCard extends StatelessWidget {
  const _OptionalCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hasContent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool hasContent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 82,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasContent ? kAuthGold : _kBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color:
                    hasContent ? kAuthGold : kAuthGold.withValues(alpha: 0.70),
                size: 26),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Publish Button ------------------------------------------------------------
class _SelectedOfferPhotos extends StatelessWidget {
  const _SelectedOfferPhotos({
    required this.photos,
    required this.onRemoveAt,
  });

  final List<_PendingOfferPhoto> photos;
  final ValueChanged<int> onRemoveAt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 90,
                height: 90,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorder),
                ),
                child: Image.file(photo.file, fit: BoxFit.cover),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => onRemoveAt(index),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 14,
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

class _SelectedOfferDocument extends StatelessWidget {
  const _SelectedOfferDocument({
    required this.document,
    required this.onRemove,
  });

  final _PendingOfferDocument document;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.fileText,
              color: kAuthGold,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  document.extension.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.trash2,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAuthGold,
          disabledBackgroundColor: kAuthGold.withValues(alpha: 0.50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                "Publier l'offre",
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

// -- Picker Sheet --------------------------------------------------------------
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          // Options
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: options.length,
              separatorBuilder: (_, __) => Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (_, i) {
                final opt = options[i];
                final isSelected = opt == selected;
                return ListTile(
                  onTap: () => onSelect(opt),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  title: Text(
                    opt,
                    style: GoogleFonts.inter(
                      color: isSelected ? kAuthGold : Colors.white,
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(LucideIcons.check,
                          color: kAuthGold, size: 18)
                      : null,
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// -- Instructions Sheet --------------------------------------------------------
class _InstructionsSheet extends StatelessWidget {
  const _InstructionsSheet({required this.ctrl});
  final TextEditingController ctrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Instructions spéciales',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33D6A85A)),
              ),
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: ctrl,
                maxLines: 5,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'Précisez toute instruction particulière pour l\'intervenant...',
                  hintStyle: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAuthGold,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  'Confirmer',
                  style: GoogleFonts.inter(
                    color: Colors.black,
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
  }
}
