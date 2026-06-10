import 'package:flutter/material.dart';
import '../models/hotel_models.dart';
import '../providers/hotel_provider.dart';
import 'add_staff_screen.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'supervisor_rooms_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class SupervisorDashboard extends StatelessWidget {
  const SupervisorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HotelProvider>(context);
    final user = provider.currentUser;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    int vendu = provider.rooms.where((r) => r.status == 'Vendu').length;
    int checkout = provider.rooms.where((r) => r.status == 'Checkout').length;
    int service =
        provider.rooms.where((r) => r.status.contains('Service')).length;
    int libre = provider.rooms.where((r) => r.status == 'Libre').length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 40.0 : 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "BONJOUR, ${user?.firstName.toUpperCase() ?? 'SUPERVISEUR'}",
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Vue d'ensemble",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontFamily: 'Eurostile',
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ProfileScreen())),
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1))),
                          child: const Icon(LucideIcons.user,
                              color: Colors.amber, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () async {
                          final hotelProvider = Provider.of<HotelProvider>(
                              context,
                              listen: false);
                          await hotelProvider.logout();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AuthScreen()),
                                (route) => false);
                          }
                        },
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1))),
                          child: const Icon(LucideIcons.logOut,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 30),
              Expanded(
                child: GridView.count(
                  crossAxisCount: isDesktop ? 3 : 1,
                  childAspectRatio: isDesktop ? 1.6 : 1.7,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildModernCard(
                      context,
                      title: "NETTOYAGE",
                      subtitle: "Chambres en service",
                      count: service,
                      icon: LucideIcons.sprayCan,
                      color: const Color(0xFF3B82F6),
                      onTap: () => _goToRooms(context, 'Service'),
                    ),
                    _buildModernCard(
                      context,
                      title: "CHECKOUT",
                      subtitle: "Départs aujourd'hui",
                      count: checkout,
                      icon: LucideIcons.logOut,
                      color: const Color(0xFFF59E0B),
                      onTap: () => _goToRooms(context, 'Checkout'),
                    ),
                    _buildModernCard(
                      context,
                      title: "VENDU",
                      subtitle: "Chambres occupées",
                      count: vendu,
                      icon: LucideIcons.key,
                      color: const Color(0xFFEF4444),
                      onTap: () => _goToRooms(context, 'Vendu'),
                    ),
                    _buildModernCard(
                      context,
                      title: "DISPONIBLES",
                      subtitle: "Prêtes à vendre",
                      count: libre,
                      icon: LucideIcons.checkCircle,
                      color: const Color(0xFF10B981),
                      onTap: () => _goToRooms(context, 'Libre'),
                    ),
                    _buildActionCard(
                      context,
                      title: "GÉRER L'ÉQUIPE",
                      subtitle: "Ajouter Staff/Superviseur",
                      icon: LucideIcons.userPlus,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AddStaffScreen(
                                  currentUserRole:
                                      user?.role ?? UserRoles.supervisor))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToRooms(BuildContext context, String filter) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SupervisorRoomsScreen(
              filterStatus: filter,
              title: filter == 'ALL' ? 'Toutes les chambres' : filter)),
    );
  }

  Widget _buildModernCard(BuildContext context,
      {required String title,
      required String subtitle,
      required int count,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Stack(
          children: [
            Positioned(
                right: -20,
                bottom: -20,
                child:
                    Icon(icon, size: 100, color: color.withValues(alpha: 0.1))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  Text("$count",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Eurostile')),
                  Row(
                    children: [
                      Text(subtitle,
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 12)),
                      const Spacer(),
                      Icon(LucideIcons.arrowRight,
                          color: Colors.grey[600], size: 18)
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

  Widget _buildActionCard(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.amber, borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: Colors.black, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.amber, size: 28)),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.7),
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
