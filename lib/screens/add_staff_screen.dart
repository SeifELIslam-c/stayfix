import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/hotel_models.dart';
import '../providers/hotel_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

class AddStaffScreen extends StatefulWidget {
  final String currentUserRole;
  final bool isAddingSupervisorMode;

  const AddStaffScreen(
      {super.key,
      required this.currentUserRole,
      this.isAddingSupervisorMode = false});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final String googleScriptUrl =
      "https://script.google.com/macros/s/AKfycbzYxUgzZBT9GlVdrAZX-Idz3uybDM_3XiOTe331CtaUibmPT8QK-FPZHkjPG9wPcABAeA/exec";

  String? _selectedRole;
  String? _selectedManagerId;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAddingSupervisorMode) {
      _selectedRole = UserRoles.supervisor;
    }
  }

  List<Map<String, dynamic>> get _roles {
    if (widget.currentUserRole == UserRoles.director) {
      if (widget.isAddingSupervisorMode) {
        return [
          {
            'id': UserRoles.supervisor,
            'label': 'Superviseur',
            'icon': LucideIcons.eye
          }
        ];
      } else {
        return [
          {
            'id': UserRoles.receptionManager,
            'label': 'Dir. Réception',
            'icon': LucideIcons.conciergeBell
          },
          {
            'id': UserRoles.housekeepingManager,
            'label': 'Dir. Propreté',
            'icon': LucideIcons.sparkles
          },
          {
            'id': UserRoles.maintenanceManager,
            'label': 'Dir. Maintenance',
            'icon': LucideIcons.hammer
          },
        ];
      }
    } else {
      return [
        {
          'id': UserRoles.supervisor,
          'label': 'Superviseur',
          'icon': LucideIcons.eye
        },
        {
          'id': UserRoles.houseman,
          'label': 'Houseman',
          'icon': LucideIcons.shirt
        },
        {
          'id': UserRoles.housekeeping,
          'label': 'Valet/Femme',
          'icon': LucideIcons.sprayCan
        },
        {
          'id': UserRoles.staff,
          'label': 'Staff Standard',
          'icon': LucideIcons.user
        },
      ];
    }
  }

  Future<void> _sendEmailViaGoogleScript(
      {required String name,
      required String email,
      required String username,
      required String password}) async {
    try {
      final response = await http.post(
        Uri.parse(googleScriptUrl),
        body: json.encode({
          'to_email': email,
          'name': name,
          'username': username,
          'password': password
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 302) {
        debugPrint("Email Sent");
      }
    } catch (e) {
      debugPrint("Error Google Script: $e");
    }
  }

  void _submit() async {
    if (_selectedRole == null ||
        _firstNameController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Veuillez remplir tous les champs obligatoires"),
          backgroundColor: Colors.redAccent));
      return;
    }

    if (widget.currentUserRole == UserRoles.director &&
        widget.isAddingSupervisorMode &&
        _selectedManagerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Veuillez sélectionner un directeur pour ce superviseur"),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);

    String finalRole = _selectedRole!;
    if (widget.isAddingSupervisorMode && _selectedManagerId != null) {
      final provider = Provider.of<HotelProvider>(context, listen: false);
      final manager =
          provider.hotelStaff.firstWhere((u) => u.id == _selectedManagerId);
      String cleanManagerRole = manager.role.replaceAll('Dir. ', '');
      finalRole = "Superviseur ($cleanManagerRole)";
    }

    await Provider.of<HotelProvider>(context, listen: false).addStaffMember(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      role: finalRole,
    );

    await _sendEmailViaGoogleScript(
      name: "${_firstNameController.text} ${_lastNameController.text}",
      email: _emailController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Membre ajouté avec succès"),
          backgroundColor: Colors.green));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: const Text("AJOUTER UN MEMBRE",
            style:
                TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
      ),
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.only(left: 24, right: 24, top: 10, bottom: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("SÉLECTIONNER LE RÔLE",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _roles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _buildRoleCard(_roles[index]),
              ),
            ),
            const SizedBox(height: 30),

            if (widget.currentUserRole == UserRoles.director &&
                widget.isAddingSupervisorMode) ...[
              const Text("RATTACHER AU DIRECTEUR",
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildManagerDropdown(),
              const SizedBox(height: 30),
            ],

            const Text("INFORMATIONS",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildInput("Prénom", _firstNameController, LucideIcons.user),
            _buildInput("Nom", _lastNameController, LucideIcons.user),
            _buildInput("Email", _emailController, LucideIcons.mail),
            _buildInput("Téléphone", _phoneController, LucideIcons.phone),

            const SizedBox(height: 30),
            const Text("ACCÈS",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildInput(
                "Nom d'utilisateur", _usernameController, LucideIcons.atSign),
            _buildInput("Mot de passe", _passwordController, LucideIcons.lock,
                isPassword: true),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Text("ENREGISTRER",
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(Map<String, dynamic> role) {
    final isSelected = _selectedRole == role['id'];
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role['id']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 105,
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Colors.amber : Colors.transparent,
              width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(role['icon'],
                color: isSelected ? Colors.amber : Colors.white, size: 30),
            const SizedBox(height: 12),
            Text(
              role['label'],
              style: TextStyle(
                  color: isSelected ? Colors.amber : Colors.grey[400],
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(
      String label, TextEditingController controller, IconData icon,
      {bool isPassword = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Colors.grey[600], size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildManagerDropdown() {
    return Consumer<HotelProvider>(builder: (context, provider, child) {
      final managers = provider.hotelStaff.where((u) {
        return u.role == UserRoles.receptionManager ||
            u.role == UserRoles.housekeepingManager ||
            u.role == UserRoles.maintenanceManager ||
            u.role.contains('Dir.');
      }).toList();

      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.transparent),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            dropdownColor: const Color(0xFF27272A),
            value: _selectedManagerId,
            hint: Text("Choisir un directeur...",
                style: TextStyle(color: Colors.grey[600])),
            isExpanded: true,
            icon: const Icon(LucideIcons.chevronDown, color: Colors.grey),
            items: managers.isEmpty
                ? []
                : managers.map((manager) {
                    return DropdownMenuItem<String>(
                      value: manager.id,
                      child: Text("${manager.fullName} (${manager.role})",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    );
                  }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedManagerId = val;
              });
            },
          ),
        ),
      );
    });
  }
}
