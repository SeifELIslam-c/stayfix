import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/hotel_provider.dart';
import 'dashboard_screen.dart';
import 'auth_screen.dart';
import 'manager_profile_config.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  String _propertyName = 'Hôtel';
  String _propertyPlural = 'Hôtels';
  IconData _propertyIcon = LucideIcons.building;
  bool _isInitLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserConfig();
  }

  Future<void> _loadUserConfig() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists && mounted) {
          final type = resolveManagerProfileValue(doc.data());
          setState(() {
            switch (type) {
              case 'building_manager':
                _propertyName = 'Immeuble';
                _propertyPlural = 'Immeubles';
                _propertyIcon = LucideIcons.home;
                break;
              case 'rental_building':
                _propertyName = 'Immeuble locatif';
                _propertyPlural = 'Immeubles locatifs';
                _propertyIcon = LucideIcons.building;
                break;
              case 'villa_owner':
                _propertyName = 'Villa';
                _propertyPlural = 'Villas';
                _propertyIcon = LucideIcons.palmtree;
                break;
              case 'apartment_condo_owner':
                _propertyName = 'Appartement';
                _propertyPlural = 'Appartements';
                _propertyIcon = LucideIcons.doorOpen;
                break;
              default:
                _propertyName = 'Hôtel';
                _propertyPlural = 'Hôtels';
                _propertyIcon = LucideIcons.building;
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading user config: $e');
      }
    }

    if (mounted) {
      await Provider.of<HotelProvider>(context, listen: false).fetchMyHotels();
      if (mounted) {
        setState(() => _isInitLoaded = true);
      }
    }
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final provider = Provider.of<HotelProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF18181B).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
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
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_propertyIcon, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'NOUVELLE $_propertyName'.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _buildTextField(
                controller: nameController,
                label: 'Nom de $_propertyName',
                icon: _propertyIcon,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: locationController,
                label: 'Localisation',
                icon: LucideIcons.mapPin,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        locationController.text.isNotEmpty) {
                      Navigator.pop(ctx);
                      await provider.createHotel(
                        nameController.text.trim(),
                        locationController.text.trim(),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'CRÉER',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Consumer<HotelProvider>(
          builder: (context, provider, child) {
            if (provider.currentUser == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                }
              });
              return const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18181B),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.logOut,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        onPressed: () async {
                          await provider.logout();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthScreen(),
                              ),
                              (route) => false,
                            );
                          }
                        },
                      ),
                      const Text(
                        'STAYFIX',
                        style: TextStyle(
                          color: Colors.amber,
                          fontFamily: 'Times New Roman',
                          fontSize: 16,
                          letterSpacing: 4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'Mes $_propertyPlural',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ).animate().fadeIn().slideX(),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: !_isInitLoaded || provider.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.amber),
                        )
                      : provider.myHotels.isEmpty
                          ? _buildEmptyState(context)
                          : _buildList(provider),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Consumer<HotelProvider>(
        builder: (context, provider, child) {
          if (provider.myHotels.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onPressed: () => _showCreateDialog(context),
            child: const Icon(LucideIcons.plus),
          ).animate().scale(delay: 400.ms);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return RefreshIndicator(
      color: Colors.amber,
      backgroundColor: const Color(0xFF18181B),
      onRefresh: () =>
          Provider.of<HotelProvider>(context, listen: false).fetchMyHotels(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: const BoxDecoration(
                    color: Color(0xFF18181B),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_propertyIcon, size: 70, color: Colors.amber),
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 32),
                Text(
                  'Aucun(e) $_propertyName trouvé(e).',
                  style: TextStyle(color: Colors.grey[400], fontSize: 16),
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: () => _showCreateDialog(context),
                  icon: const Icon(LucideIcons.plus, size: 20),
                  label: Text(
                    'Créer votre premier $_propertyName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(HotelProvider provider) {
    return RefreshIndicator(
      color: Colors.amber,
      backgroundColor: const Color(0xFF18181B),
      onRefresh: () => provider.fetchMyHotels(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: provider.myHotels.length,
        itemBuilder: (context, index) {
          final hotel = provider.myHotels[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                provider.setHotel(hotel);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_propertyIcon, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hotel.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.mapPin,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hotel.location,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.1);
        },
      ),
    );
  }
}
