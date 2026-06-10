import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/hotel_models.dart';
import '../providers/hotel_provider.dart';
import 'supervisor_dashboard.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  String _searchQuery = "";
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HotelProvider>(context);
    final user = provider.currentUser;
    final rooms = provider.rooms;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    if (user != null && user.role.contains('Superviseur')) {
      return const SupervisorDashboard();
    }

    Map<String, List<Room>> groupedRooms = {};
    for (var room in rooms) {
      if (_searchQuery.isNotEmpty && !room.number.contains(_searchQuery)) {
        continue;
      }
      if (!groupedRooms.containsKey(room.floor)) {
        groupedRooms[room.floor] = [];
      }
      groupedRooms[room.floor]!.add(room);
    }

    var sortedFloorKeys = groupedRooms.keys.toList()
      ..sort((a, b) {
        int numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        int numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return numA.compareTo(numB);
      });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("GESTION DES CHAMBRES",
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                letterSpacing: 2,
                fontWeight: FontWeight.bold)),
        actions: [
          if (provider.isDirector && rooms.isEmpty)
            IconButton(
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.amber))
                  : const Icon(LucideIcons.database, color: Colors.red),
              tooltip: "Créer les chambres (Seed)",
              onPressed: () async {
                setState(() => _isGenerating = true);
                await provider.generateDefaultRooms();
                setState(() => _isGenerating = false);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Container(
              constraints:
                  BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Rechercher (ex: 205)",
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                  prefixIcon:
                      const Icon(LucideIcons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
          ),
          rooms.isEmpty && !_isGenerating
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                              color: Color(0xFF18181B), shape: BoxShape.circle),
                          child: const Icon(LucideIcons.bedDouble,
                              size: 50, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        Text("Aucune chambre disponible.",
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  ),
                )
              : Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 40 : 16, vertical: 10),
                    physics: const BouncingScrollPhysics(),
                    itemCount: sortedFloorKeys.length,
                    itemBuilder: (ctx, index) {
                      String floorName = sortedFloorKeys[index];
                      List<Room> floorRooms = groupedRooms[floorName]!;
                      return FloorExpandableSection(
                        floorName: floorName,
                        rooms: floorRooms,
                        provider: provider,
                        user: user!,
                        isDesktop: isDesktop,
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}

class FloorExpandableSection extends StatefulWidget {
  final String floorName;
  final List<Room> rooms;
  final HotelProvider provider;
  final HotelUser user;
  final bool isDesktop;

  const FloorExpandableSection({
    super.key,
    required this.floorName,
    required this.rooms,
    required this.provider,
    required this.user,
    required this.isDesktop,
  });

  @override
  State<FloorExpandableSection> createState() => _FloorExpandableSectionState();
}

class _FloorExpandableSectionState extends State<FloorExpandableSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    bool isDirector = widget.user.role == UserRoles.director;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (bool expanded) {
            setState(() => _isExpanded = expanded);
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          collapsedIconColor: Colors.amber,
          iconColor: Colors.amber,
          title: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Text(widget.floorName.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ),
              const SizedBox(width: 12),
              Text("${widget.rooms.length} Chambres",
                  style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          trailing: isDirector
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.edit3,
                          size: 16, color: Colors.grey),
                      onPressed: () => _showModernRenameDialog(
                          context, widget.provider, widget.floorName),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.plusCircle,
                          color: Colors.amber, size: 20),
                      onPressed: () => _showModernAddRoomBottomSheet(
                          context, widget.provider, widget.floorName),
                    ),
                    Icon(
                      _isExpanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                )
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: widget.rooms
                    .map((room) => _buildRoomCard(context, widget.provider,
                        room, widget.user, widget.isDesktop))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, HotelProvider provider, Room room,
      HotelUser user, bool isDesktop) {
    bool isDirector = user.role == UserRoles.director;
    bool isReception = user.role.contains('Réception') ||
        user.role == UserRoles.receptionManager;

    String statusText;
    Color statusColor;

    switch (room.status) {
      case 'Vendu':
        statusText = "VENDU";
        statusColor = const Color(0xFFEF4444);
        break;
      case 'Checkout':
        statusText = "CHECKOUT";
        statusColor = const Color(0xFFF59E0B);
        break;
      case 'Service Full':
        statusText = "SRV FULL";
        statusColor = const Color(0xFF3730A3);
        break;
      case 'Service Normal':
        statusText = "SRV NORM";
        statusColor = const Color(0xFF0EA5E9);
        break;
      case 'Libre':
      default:
        statusText = "LIBRE";
        statusColor = const Color(0xFF10B981);
        break;
    }

    double cardWidth = isDesktop ? 160 : 155;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                room.number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Eurostile'),
              ),
              InkWell(
                onTap: isDirector
                    ? () => provider.updateRoomType(
                        room.id, room.type == 'King' ? 'Queen' : 'King')
                    : null,
                child: Row(
                  children: [
                    Icon(LucideIcons.crown, size: 12, color: Colors.amber[500]),
                    const SizedBox(width: 4),
                    Text(room.type,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
          ),

          if (isReception) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statusLetterBtn(
                    letter: 'L',
                    color: const Color(0xFF10B981),
                    onTap: () => provider.updateRoomStatus(room.id, 'Libre')),
                _statusLetterBtn(
                    letter: 'V',
                    color: const Color(0xFFEF4444),
                    onTap: () => provider.updateRoomStatus(room.id, 'Vendu')),
                _statusLetterBtn(
                    letter: 'C',
                    color: const Color(0xFFF59E0B),
                    onTap: () =>
                        provider.updateRoomStatus(room.id, 'Checkout')),
                _statusLetterBtn(
                    letter: 'F',
                    color: const Color(0xFF3730A3),
                    onTap: () =>
                        provider.updateRoomStatus(room.id, 'Service Full')),
                _statusLetterBtn(
                    letter: 'N',
                    color: const Color(0xFF0EA5E9),
                    onTap: () =>
                        provider.updateRoomStatus(room.id, 'Service Normal')),
              ],
            )
          ],

          if (isDirector)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => provider.deleteRoom(room.id),
                  child: const Icon(LucideIcons.trash2,
                      size: 16, color: Color(0xFFEF4444)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusLetterBtn(
      {required String letter,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _showModernAddRoomBottomSheet(
      BuildContext context, HotelProvider provider, String floor) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B).withValues(alpha: 0.95),
                border: Border(
                    top:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1))),
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
                              borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: const Icon(LucideIcons.plus,
                              color: Colors.amber, size: 24)),
                      const SizedBox(width: 16),
                      const Text("AJOUTER UNE CHAMBRE",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05))),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: "Numéro (ex: 205)",
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon:
                            const Icon(LucideIcons.hash, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          provider.addRoom(controller.text, floor);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text("CRÉER LA CHAMBRE",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showModernRenameDialog(
      BuildContext context, HotelProvider provider, String oldFloorName) {
    final controller = TextEditingController(text: oldFloorName);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B).withValues(alpha: 0.95),
                border: Border(
                    top:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1))),
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
                              borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: const Icon(LucideIcons.edit3,
                              color: Colors.white, size: 24)),
                      const SizedBox(width: 16),
                      const Text("RENOMMER L'ÉTAGE",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05))),
                    child: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: "Nouveau nom",
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon:
                            const Icon(LucideIcons.layers, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          provider.renameFloor(oldFloorName, controller.text);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text("ENREGISTRER",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
