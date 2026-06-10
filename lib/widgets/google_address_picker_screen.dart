import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../screens/auth_screen.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';

const _kPickerBg = Color(0xFF070707);
const _kPickerCard = Color(0xFF111111);
const _kPickerMuted = Color(0xFF181818);
const _kPickerBorder = Color(0x33D6A85A);

class GoogleAddressPickerScreen extends StatefulWidget {
  const GoogleAddressPickerScreen({
    super.key,
    required this.title,
    required this.apiKey,
    this.initialAddress = '',
    this.isModal = false,
    this.returnSelectionObject = false,
  });

  final String title;
  final String apiKey;
  final String initialAddress;
  final bool isModal;
  final bool returnSelectionObject;

  @override
  State<GoogleAddressPickerScreen> createState() =>
      _GoogleAddressPickerScreenState();
}

class _GoogleAddressPickerScreenState extends State<GoogleAddressPickerScreen> {
  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(36.7538, 3.0588),
    zoom: 13.5,
  );

  final TextEditingController _searchController = TextEditingController();
  final Completer<GoogleMapController> _mapController = Completer();
  final List<_AddressSuggestion> _suggestions = <_AddressSuggestion>[];
  Timer? _debounce;

  CameraPosition _cameraPosition = _fallbackCamera;
  Marker? _selectedMarker;
  Position? _currentPosition;
  String? _selectedAddress;
  LatLng? _selectedLatLng;
  bool _isMapMoving = false;
  bool _isBootstrapping = true;
  bool _isLocating = true;
  bool _isSearching = false;
  bool _isResolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialAddress.trim();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _resolveCurrentLocation();
      if (_currentPosition != null) {
        await _selectFromMap(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        );
      } else if (widget.initialAddress.trim().isNotEmpty) {
        await _searchByText(widget.initialAddress.trim(),
            autoSelectFirst: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    }
  }

  Future<void> _resolveCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 8),
        ),
      );
      final target = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _cameraPosition = CameraPosition(target: target, zoom: 16.2);
        _isLocating = false;
      });

      await _animateCamera(target, zoom: 16.2);
    } catch (_) {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _animateCamera(LatLng target, {double zoom = 16}) async {
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom)),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchByText(value.trim());
    });
  }

  Future<void> _searchByText(
    String query, {
    bool autoSelectFirst = false,
  }) async {
    if (query.length < 3) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _suggestions.clear();
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        <String, String>{
          'input': query,
          'key': widget.apiKey,
          'language': 'fr',
          'types': 'address',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = (body['predictions'] as List<dynamic>? ?? <dynamic>[])
          .map((entry) => entry as Map<String, dynamic>)
          .map(
            (entry) => _AddressSuggestion(
              placeId: (entry['place_id'] as String?) ?? '',
              description: (entry['description'] as String?)?.trim() ?? '',
            ),
          )
          .where((entry) =>
              entry.placeId.isNotEmpty && entry.description.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _suggestions
          ..clear()
          ..addAll(predictions);
        _isSearching = false;
      });

      if (autoSelectFirst && predictions.isNotEmpty) {
        await _selectSuggestion(predictions.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _suggestions.clear();
      });
    }
  }

  Future<void> _selectSuggestion(_AddressSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    setState(() => _isResolvingAddress = true);
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        <String, String>{
          'place_id': suggestion.placeId,
          'fields': 'formatted_address,geometry',
          'key': widget.apiKey,
          'language': 'fr',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result =
          body['result'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final geometry =
          result['geometry'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final location =
          geometry['location'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final target = LatLng(lat, lng);
      if (!mounted) return;

      setState(() {
        _selectedAddress = (result['formatted_address'] as String?)?.trim() ??
            suggestion.description;
        _selectedLatLng = target;
        _searchController.text = _selectedAddress!;
        _selectedMarker = Marker(
          markerId: const MarkerId('selected-address'),
          position: target,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        );
        _suggestions.clear();
        _cameraPosition = CameraPosition(target: target, zoom: 17);
      });

      await _animateCamera(target, zoom: 17);
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  Future<void> _selectFromMap(
    LatLng position, {
    bool updateSearchText = true,
  }) async {
    setState(() {
      _selectedMarker = Marker(
        markerId: const MarkerId('selected-address'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      );
      _selectedLatLng = position;
      _selectedAddress = null;
      _isResolvingAddress = true;
      _suggestions.clear();
    });

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        <String, String>{
          'latlng': '${position.latitude},${position.longitude}',
          'key': widget.apiKey,
          'language': 'fr',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? <dynamic>[];
      final address = results.isNotEmpty
          ? ((results.first as Map<String, dynamic>)['formatted_address']
                  as String?)
              ?.trim()
          : null;

      if (!mounted) return;
      setState(() {
        _selectedAddress = address ?? 'Point choisi sur la carte';
        if (updateSearchText) {
          _searchController.text = _selectedAddress!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedAddress = 'Point choisi sur la carte');
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  void _confirmSelection() {
    final address = _selectedAddress?.trim();
    if (address == null || address.isEmpty) return;

    if (widget.returnSelectionObject) {
      Navigator.pop(
        context,
        GoogleAddressSelection(
          address: address,
          latitude: _selectedLatLng?.latitude,
          longitude: _selectedLatLng?.longitude,
        ),
      );
      return;
    }

    Navigator.pop(context, address);
  }

  Widget _buildBody(BuildContext context) {
    return Stack(
      children: [
        if (_isBootstrapping)
          const ColoredBox(color: Color(0xFFE8F6EB))
        else
          GoogleMap(
            initialCameraPosition: _cameraPosition,
            myLocationEnabled: _currentPosition != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: false,
            markers: _selectedMarker == null
                ? const <Marker>{}
                : <Marker>{_selectedMarker!},
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
            onCameraMoveStarted: () {
              if (_suggestions.isNotEmpty) {
                setState(() => _suggestions.clear());
              }
              _isMapMoving = true;
            },
            onTap: _selectFromMap,
            onCameraMove: (position) => _cameraPosition = position,
            onCameraIdle: () {
              if (!_isMapMoving || _isBootstrapping || _isResolvingAddress) {
                return;
              }
              _isMapMoving = false;
              unawaited(
                _selectFromMap(
                  _cameraPosition.target,
                  updateSearchText: false,
                ),
              );
            },
          ),
        IgnorePointer(
          ignoring: true,
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.mapPin,
                    color: kAuthGold,
                    size: 34,
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.18, 0.45, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.48),
                Colors.black.withValues(alpha: 0.16),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.08),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    _CircleMapButton(
                      icon: LucideIcons.arrowLeft,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          color: widget.isModal ? Colors.white : Colors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: _kPickerCard,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _kPickerBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        cursorColor: kAuthGold,
                        decoration: InputDecoration(
                          hintText: 'Rechercher une adresse',
                          hintStyle: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            LucideIcons.search,
                            color: kAuthGold,
                            size: 18,
                          ),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kAuthGold,
                                    ),
                                  ),
                                )
                              : (_searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _searchController.clear();
                                          _suggestions.clear();
                                        });
                                      },
                                      icon: const Icon(
                                        LucideIcons.x,
                                        color: Colors.white70,
                                        size: 18,
                                      ),
                                    )),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 240),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _kPickerBorder),
                            ),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final suggestion = _suggestions[index];
                              return InkWell(
                                onTap: () => _selectSuggestion(suggestion),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _kPickerMuted,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        LucideIcons.mapPin,
                                        color: kAuthGold,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          suggestion.description,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    children: [
                      _CircleMapButton(
                        icon: LucideIcons.locateFixed,
                        onTap: _isLocating
                            ? null
                            : () async {
                                await _resolveCurrentLocation();
                                if (_currentPosition != null) {
                                  await _selectFromMap(
                                    LatLng(
                                      _currentPosition!.latitude,
                                      _currentPosition!.longitude,
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                      _CircleMapButton(
                        icon: LucideIcons.navigation,
                        onTap: () => _animateCamera(
                          _cameraPosition.target,
                          zoom: (_cameraPosition.zoom + 1).clamp(3.0, 20.0),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CircleMapButton(
                        icon: LucideIcons.minus,
                        onTap: () => _animateCamera(
                          _cameraPosition.target,
                          zoom: (_cameraPosition.zoom - 1).clamp(3.0, 20.0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    color: _kPickerCard,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _kPickerBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const _InfoChip(
                            icon: LucideIcons.briefcase,
                            label: 'Stayfix',
                          ),
                          const SizedBox(width: 10),
                          _InfoChip(
                            icon: LucideIcons.clock3,
                            label: _isResolvingAddress
                                ? 'Recherche...'
                                : 'Adresse precise',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _selectedAddress ??
                            'Touchez la carte ou recherchez une adresse.',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedAddress == null
                            ? 'Glissez la carte, zoomez ou recherchez une adresse pour positionner le repere.'
                            : 'Glissez la carte si besoin puis confirmez cette position.',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      if (_selectedAddress != null) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _confirmSelection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAuthGold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            icon:
                                const Icon(LucideIcons.checkCircle2, size: 18),
                            label: Text(
                              'Confirmer adresse',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isBootstrapping)
          const SafeArea(
            child: Center(
              child: CircularProgressIndicator(
                color: kAuthGold,
                strokeWidth: 2.4,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isModal) {
      return ColoredBox(
        color: _kPickerBg,
        child: _buildBody(context),
      );
    }

    return Scaffold(
      backgroundColor: _kPickerBg,
      body: _buildBody(context),
    );
  }
}

class GoogleAddressSelection {
  const GoogleAddressSelection({
    required this.address,
    this.latitude,
    this.longitude,
  });

  final String address;
  final double? latitude;
  final double? longitude;
}

class _AddressSuggestion {
  const _AddressSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

class _CircleMapButton extends StatelessWidget {
  const _CircleMapButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _kPickerCard,
            shape: BoxShape.circle,
            border: Border.all(color: _kPickerBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kPickerMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kPickerBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kAuthGold, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
