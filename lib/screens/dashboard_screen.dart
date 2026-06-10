import 'package:flutter/material.dart';
import 'package:stayfix/models/hotel_models.dart';
import 'package:stayfix/providers/hotel_provider.dart';
import 'package:stayfix/screens/add_staff_screen.dart';
import 'package:stayfix/screens/auth_screen.dart';
import 'package:stayfix/screens/profile_screen.dart';
import 'package:stayfix/screens/room_list_screen.dart';
import 'package:stayfix/screens/selection_screen.dart';
import 'package:stayfix/screens/supervisor_dashboard.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initData();
    }
  }

  void _initData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<HotelProvider>(context, listen: false);
        if (provider.currentUser != null && provider.selectedHotel != null) {
          provider.listenToHotelData();
          provider.fetchHotelStaff();
          if (provider.currentUser!.role == UserRoles.director) {
            provider.generateDefaultRooms();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HotelProvider>(
      builder: (context, provider, child) {
        final user = provider.currentUser;

        if (_isLoggingOut) return const Scaffold(backgroundColor: Colors.black);

        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            }
          });
          return const Scaffold(backgroundColor: Colors.black);
        }

        if (user.role == UserRoles.director && provider.selectedHotel == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const SelectionScreen()),
              );
            }
          });
          return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                  child: CircularProgressIndicator(color: Colors.amber)));
        }

        if (user.role.contains('Superviseur')) {
          return const SupervisorDashboard();
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _buildAppBar(context, user, provider),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                _buildRoleBasedView(user, provider),
              ],
            ),
          ),
          floatingActionButton: _buildFab(context, user),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, HotelUser user, HotelProvider provider) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      title: InkWell(
        onTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  user.fullName.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.edit2, size: 12, color: Colors.grey),
              ],
            ),
            Text(
              "${user.role} • ${provider.selectedHotel?.name ?? '...'}",
              style: TextStyle(color: Colors.grey[500], fontSize: 10),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.logOut, color: Colors.white),
          onPressed: () {
            _isLoggingOut = true;
            final hotelProvider =
                Provider.of<HotelProvider>(context, listen: false);
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false);
            Future.delayed(const Duration(milliseconds: 200),
                () => hotelProvider.logout());
          },
        )
      ],
    );
  }

  Widget _buildRoleBasedView(HotelUser user, HotelProvider provider) {
    if (user.role == UserRoles.director) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: _statCard("Total Staff",
                        "${provider.hotelStaff.length}", LucideIcons.users)),
                const SizedBox(width: 12),
                Expanded(child: _roomStatsCard(context, provider)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(LucideIcons.userPlus, size: 16),
                    label: const Text("Ajouter Directeur",
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF18181B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1))),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AddStaffScreen(
                                currentUserRole: user.role,
                                isAddingSupervisorMode: false))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(LucideIcons.eye, size: 16),
                    label: const Text("Ajouter Superviseur",
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.withValues(alpha: 0.1),
                      foregroundColor: Colors.amber,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                              color: Colors.amber, width: 1.5)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AddStaffScreen(
                                currentUserRole: user.role,
                                isAddingSupervisorMode: true))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Text("DIRECTEURS DE DÉPARTEMENT",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: provider.hotelStaff
                      .where((u) => u.role != UserRoles.director)
                      .isEmpty
                  ? Center(
                      child: Text("Aucun personnel ajouté.",
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: provider.hotelStaff.length,
                      itemBuilder: (ctx, i) {
                        final staff = provider.hotelStaff[i];
                        if (staff.role == UserRoles.director)
                          return const SizedBox.shrink();
                        return _buildStaffTile(staff);
                      },
                    ),
            ),
          ],
        ),
      );
    }

    if (user.role == UserRoles.housekeeping ||
        user.role == UserRoles.houseman ||
        user.role == UserRoles.staff) {
      final tasks = provider.rooms
          .where((r) => r.status.contains('Service') || r.status == 'Checkout')
          .toList();
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statCard("À Nettoyer", "${tasks.length}", LucideIcons.sprayCan),
            const SizedBox(height: 24),
            const Text("MES TÂCHES",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text("Aucune chambre à nettoyer.",
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (ctx, i) {
                        final r = tasks[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border(
                                  left: BorderSide(
                                      color: r.status == 'Checkout'
                                          ? Colors.amber
                                          : Colors.indigo,
                                      width: 4))),
                          child: ListTile(
                            leading: const Icon(LucideIcons.bed,
                                color: Colors.white),
                            title: Text("Chambre ${r.number}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(r.status.toUpperCase(),
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 10)),
                            trailing: IconButton(
                                icon: const Icon(LucideIcons.checkCircle,
                                    color: Colors.green),
                                onPressed: () =>
                                    provider.updateRoomStatus(r.id, 'Libre')),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      );
    }

    bool canViewRooms = [
      UserRoles.housekeepingManager,
      UserRoles.maintenanceManager,
      UserRoles.receptionManager
    ].contains(user.role);
    if (canViewRooms) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _roomStatsCard(context, provider),
            const SizedBox(height: 24),
            const Text("ÉTAT DES CHAMBRES",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
              child: provider.rooms.isEmpty
                  ? Center(
                      child: Text("Aucune chambre.",
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: provider.rooms.length,
                      itemBuilder: (ctx, i) {
                        final r = provider.rooms[i];
                        if (r.status == 'Libre') return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: Icon(LucideIcons.bed,
                                color: r.status == 'Vendu'
                                    ? Colors.redAccent
                                    : Colors.amber),
                            title: Text("Chambre ${r.number}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(r.status.toUpperCase(),
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 10)),
                            trailing: Text(r.type,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(color: Color(0xFF27272A), height: 30),
            const Text("MON ÉQUIPE",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              flex: 1,
              child: provider.hotelStaff.isEmpty
                  ? Center(
                      child: Text("Aucune équipe.",
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView(
                      children: provider.hotelStaff
                          .where((u) =>
                              u.role != UserRoles.director &&
                              u.role != user.role)
                          .map((staff) => _buildStaffTile(staff))
                          .toList(),
                    ),
            ),
          ],
        ),
      );
    }

    return const Expanded(
        child: Center(
            child: Text("Bienvenue", style: TextStyle(color: Colors.white))));
  }

  Widget _buildStaffTile(HotelUser staff) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: Colors.amber.withValues(alpha: 0.1),
            child:
                Icon(_getRoleIcon(staff.role), color: Colors.amber, size: 18)),
        title: Text(staff.fullName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(staff.role,
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ),
    );
  }

  Widget _roomStatsCard(BuildContext context, HotelProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(LucideIcons.bed, color: Colors.grey[400], size: 24),
              InkWell(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RoomListScreen())),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.amber),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text("VIEW",
                      style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1)),
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          Text("${provider.rooms.length}",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Chambres Totales",
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    if (role.contains('Réception')) return LucideIcons.conciergeBell;
    if (role.contains('Gouvernante') || role.contains('Propreté'))
      return LucideIcons.sparkles;
    if (role.contains('Maintenance')) return LucideIcons.hammer;
    if (role.contains('Superviseur')) return LucideIcons.eye;
    return LucideIcons.user;
  }

  Widget? _buildFab(BuildContext context, HotelUser user) {
    if (user.role == UserRoles.director ||
        [UserRoles.housekeeping, UserRoles.houseman, UserRoles.staff]
            .contains(user.role)) return null;
    return FloatingActionButton(
      backgroundColor: Colors.amber,
      child: const Icon(LucideIcons.userPlus, color: Colors.black),
      onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AddStaffScreen(currentUserRole: user.role))),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[400], size: 24),
          const SizedBox(height: 16),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }
}
