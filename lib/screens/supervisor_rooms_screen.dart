import 'package:flutter/material.dart';
import '../models/hotel_models.dart';
import '../providers/hotel_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

class SupervisorRoomsScreen extends StatefulWidget {
  final String filterStatus;
  final String title;

  const SupervisorRoomsScreen(
      {super.key, required this.filterStatus, required this.title});

  @override
  State<SupervisorRoomsScreen> createState() => _SupervisorRoomsScreenState();
}

class _SupervisorRoomsScreenState extends State<SupervisorRoomsScreen> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HotelProvider>(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    List<Room> filteredRooms = provider.rooms.where((r) {
      bool matchesStatus = widget.filterStatus == 'ALL' ||
          (widget.filterStatus == 'Service'
              ? r.status.contains('Service')
              : r.status == widget.filterStatus);
      bool matchesSearch =
          _searchQuery.isEmpty || r.number.contains(_searchQuery);
      return matchesStatus && matchesSearch;
    }).toList();

    filteredRooms.sort((a, b) => a.numberAsInt.compareTo(b.numberAsInt));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        elevation: 0,
        leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: Text(widget.title.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.05))),
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
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ),
      body: filteredRooms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                          color: Color(0xFF18181B), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.searchX,
                          size: 50, color: Colors.grey)),
                  const SizedBox(height: 20),
                  Text("Aucune chambre trouvée",
                      style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 40 : 20, vertical: 20),
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: filteredRooms
                    .map((room) =>
                        _buildRoomCard(context, provider, room, isDesktop))
                    .toList(),
              ),
            ),
    );
  }

  Widget _buildRoomCard(
      BuildContext context, HotelProvider provider, Room room, bool isDesktop) {
    Color statusColor;
    String statusText;

    if (room.status == 'Vendu') {
      statusColor = const Color(0xFFEF4444);
      statusText = "VENDU";
    } else if (room.status == 'Checkout') {
      statusColor = const Color(0xFFF59E0B);
      statusText = "CHECKOUT";
    } else if (room.status.contains('Service')) {
      statusColor = const Color(0xFF3B82F6);
      statusText = "NETTOYAGE";
    } else {
      statusColor = const Color(0xFF10B981);
      statusText = "LIBRE";
    }

    double cardWidth = isDesktop ? 160 : 155;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(room.number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Eurostile')),
              Row(
                children: [
                  Icon(
                      room.type == 'King'
                          ? LucideIcons.crown
                          : LucideIcons.bedDouble,
                      size: 12,
                      color: Colors.amber[500]),
                  const SizedBox(width: 4),
                  Text(room.type,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
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
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (room.status != 'Libre')
                _buildActionBtn(
                    icon: Icons.cleaning_services,
                    color: const Color(0xFF3B82F6),
                    onTap: () =>
                        provider.updateRoomStatus(room.id, 'Service Normal')),
              if (room.status != 'Libre') const SizedBox(width: 8),
              if (room.status != 'Libre')
                _buildActionBtn(
                    icon: LucideIcons.checkCircle,
                    color: const Color(0xFF10B981),
                    onTap: () => provider.updateRoomStatus(room.id, 'Libre')),
              if (room.status == 'Libre')
                _buildActionBtn(
                    icon: LucideIcons.key,
                    color: const Color(0xFFEF4444),
                    onTap: () => provider.updateRoomStatus(room.id, 'Vendu')),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
