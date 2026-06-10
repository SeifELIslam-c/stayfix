import 'package:flutter/material.dart';
import 'package:stayfix/providers/hotel_provider.dart';
import 'package:stayfix/screens/privacy_account_center_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<HotelProvider>(context, listen: false).currentUser;
    if (user != null) {
      _emailController.text = user.email;
      _usernameController.text = user.username;
    }
  }

  void _saveChanges() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<HotelProvider>(context, listen: false);

    bool success = await provider.updateUserProfile(
      email: _emailController.text,
      username: _usernameController.text,
      password:
          _passwordController.text.isNotEmpty ? _passwordController.text : null,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(success ? "Profil mis à jour !" : "Erreur de mise à jour"),
        backgroundColor: success ? Colors.green : Colors.red,
      ));
      if (success) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("MON PROFIL",
            style: TextStyle(color: Colors.white, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF18181b),
              child: Icon(LucideIcons.user, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 30),
            _buildField(
                "Nom d'utilisateur", _usernameController, LucideIcons.user),
            const SizedBox(height: 16),
            _buildField("Email", _emailController, LucideIcons.mail),
            const SizedBox(height: 16),
            _buildField("Nouveau mot de passe (Optionnel)", _passwordController,
                LucideIcons.lock,
                isPassword: true),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrivacyAccountCenterScreen(),
                  ),
                ),
                icon: const Icon(LucideIcons.shieldCheck),
                label: const Text("CONFIDENTIALITE ET COMPTE"),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showDeleteAccountFlow(context),
                icon: const Icon(LucideIcons.trash2),
                label: const Text("SUPPRIMER MON COMPTE"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF7B7B),
                  side: const BorderSide(color: Color(0x66FF7B7B)),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("ENREGISTRER LES MODIFICATIONS"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController controller, IconData icon,
      {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF18181b),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF27272a))),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: Colors.grey),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16)),
      ),
    );
  }
}
