import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:geo_assistant/geolocator.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

class MapPage extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String title;
  final String? imageUrl;
  final bool autoRoute;

  const MapPage({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.imageUrl,
    this.autoRoute = false,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const String _geoapifyApiKey = 'f4359d5a6ce148bd8127963c3d2bbe4c';

  GoogleMapController? _mapController;
  Timer? _debounce;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late LatLng _destinationLatLng;
  LatLng? _startLatLng;
  late Set<Marker> _markers;
  List<LatLng> _polylineCoordinates = [];
  Map<PolylineId, Polyline> _polylines = {};
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  bool _isLoading = false;
  bool _isNavigating = false;
  String _selectedMode = 'drive';

  // --- Custom Navigation State ---
  List<dynamic> _routeSteps = [];
  int _currentStepIndex = 0;
  StreamSubscription<geo.Position>? _positionStream;
  bool _isAutoFollowing = true;
  double _totalDistance = 0;
  double _totalDuration = 0;
  String _currentInstruction = "Follow the route";
  double _distanceToNextStep = 0;

  @override
  void initState() {
    super.initState();
    _destinationLatLng = LatLng(widget.latitude, widget.longitude);
    _markers = {
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLatLng,
      )
    };

    _loadCustomMarker();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setStartToCurrentLocation();
      await _startRouting();
      if (widget.autoRoute) {
        _startLiveNavigation();
      }
    });
  }

  Future<void> _loadCustomMarker() async {
    BitmapDescriptor icon = await _createCustomMarker(widget.title);
    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'destination');
        _markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLatLng,
          icon: icon,
        ));
      });
    }
  }

  Future<BitmapDescriptor> _createCustomMarker(String title) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    TextSpan span = TextSpan(
      style: const TextStyle(
        color: Color(0xFF1976D2), // Blue color like Google Maps
        fontSize: 45.0,
        fontWeight: FontWeight.w600,
        shadows: [
          Shadow(offset: Offset(-3, -3), color: Colors.white),
          Shadow(offset: Offset(3, -3), color: Colors.white),
          Shadow(offset: Offset(3, 3), color: Colors.white),
          Shadow(offset: Offset(-3, 3), color: Colors.white),
          Shadow(offset: Offset(0, 0), color: Colors.white, blurRadius: 4),
        ],
      ),
      text: title,
    );
    
    TextPainter painter = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    
    double iconSize = 60.0;
    double spacing = 15.0;
    double width = painter.width + iconSize + spacing;
    double height = painter.height > iconSize ? painter.height : iconSize;
    
    // Draw Text on the left
    painter.paint(canvas, Offset(0, (height - painter.height) / 2));
    
    // Draw Icon Bubble on the right
    double iconX = painter.width + spacing;
    double iconY = (height - iconSize) / 2;
    
    Paint circlePaint = Paint()..color = const Color(0xFF1976D2);
    Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;

    Offset center = Offset(iconX + iconSize / 2, iconY + iconSize / 2);
    
    // Shadow for circle
    canvas.drawShadow(
        Path()..addOval(Rect.fromCircle(center: center, radius: iconSize / 2)),
        Colors.black,
        4.0,
        true);
        
    canvas.drawCircle(center, iconSize / 2, circlePaint);
    canvas.drawCircle(center, iconSize / 2, borderPaint);

    // Draw inner white dot (to mimic pin)
    Paint innerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, iconSize / 5, innerPaint);
    
    final ui.Image img = await pictureRecorder.endRecording().toImage(width.toInt(), height.toInt());
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _fetchSuggestions(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);
      final uri = Uri.parse(
          'https://api.geoapify.com/v1/geocode/autocomplete?text=${Uri.encodeComponent(query)}&bias=proximity:${_destinationLatLng.latitude},${_destinationLatLng.longitude}&filter=countrycode:pk&limit=15&apiKey=$_geoapifyApiKey');
      try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data['features'] as List;
          if (mounted) {
            setState(() {
              _suggestions = features
                  .map((f) => {
                        'description': f['properties']['formatted'] ?? '',
                        'lat': f['properties']['lat'],
                        'lon': f['properties']['lon'],
                        'name': f['properties']['name'] ??
                            f['properties']['city'] ??
                            '',
                      })
                  .toList();
              _showSuggestions = _suggestions.isNotEmpty;
            });
          }
        }
      } catch (e) {
        debugPrint('Search Error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _goToPlace(Map<String, dynamic> suggestion) {
    if (suggestion['lat'] == null || suggestion['lon'] == null) return;
    final newPos = LatLng(suggestion['lat'], suggestion['lon']);
    setState(() {
      _destinationLatLng = newPos;
      _searchController.text = suggestion['name'];
      _suggestions = [];
      _showSuggestions = false;
      _isNavigating = false;
      _polylines = {};
      _markers = {
        Marker(
            markerId: const MarkerId('destination'),
            position: newPos,
            infoWindow: InfoWindow(title: suggestion['name']),
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed))
      };
      
      // Update with custom marker
      _loadCustomMarker();
    });
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: newPos, zoom: 16.0)));
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
      _isNavigating = false;
      _polylines = {};
      _markers = {
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLatLng,
        )
      };
    });
    _loadCustomMarker();
    _searchFocus.unfocus();
  }

  Future<void> _setStartToCurrentLocation() async {
    try {
      debugPrint("DEBUG: Requesting location...");
      geo.Position position = await LocationHelper.determinePosition();
      debugPrint(
          "DEBUG: Location received: ${position.latitude}, ${position.longitude}");

      setState(() {
        _startLatLng = LatLng(position.latitude, position.longitude);
        _markers.add(Marker(
          markerId: const MarkerId('start_location'),
          position: _startLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: "My Location"),
        ));
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Location Found!"),
            content: Text(
                "Latitude: ${position.latitude}\nLongitude: ${position.longitude}"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c), child: const Text("OK"))
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("DEBUG: Location Error: $e");
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Location Error"),
            content: Text(
                "Problem: $e\n\nSuggestion: Make sure GPS is on and you have set a location in the emulator controls."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c), child: const Text("OK"))
            ],
          ),
        );
      }
    }
  }

  Future<void> _startRouting() async {
    if (_startLatLng == null) await _setStartToCurrentLocation();
    if (_startLatLng == null) return;

    setState(() => _isLoading = true);
    final url =
        'https://api.geoapify.com/v1/routing?waypoints=${_startLatLng!.latitude},${_startLatLng!.longitude}|${_destinationLatLng.latitude},${_destinationLatLng.longitude}&mode=$_selectedMode&apiKey=$_geoapifyApiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];
        final geometry = feature['geometry']['coordinates'];
        final properties = feature['properties'];

        _routeSteps = properties['legs'][0]['steps'];
        _totalDistance = (properties['distance'] as num).toDouble();
        _totalDuration = (properties['time'] as num).toDouble();

        List<LatLng> coords = [];
        if (geometry is List && geometry.isNotEmpty) {
          if (geometry[0] is List && geometry[0][0] is List) {
            for (var segment in geometry) {
              for (var c in (segment as List)) {
                coords.add(
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
              }
            }
          } else {
            for (var c in geometry) {
              coords.add(
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
        }
        _drawPolyline(coords,
            isLive: _isNavigating); // Preserve live color if rerouting

        setState(() {
          _isNavigating = false;
          _currentStepIndex = 0;
          _isLoading = false;
        });

        // Only reset camera to 2D bounds if we are in PLANNING mode.
        // If we are in LIVE navigation, keep the 3D follow view.
        if (_positionStream == null) {
          LatLngBounds bounds = _getBounds(_startLatLng!, _destinationLatLng);
          _mapController
              ?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
        }
      } else {
        final errorData = json.decode(response.body);
        debugPrint('Routing Error Response: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Routing Failed: ${errorData['message'] ?? 'Unknown Error'}')));
        }
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Routing Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  void _drawPolyline(List<LatLng> coords, {bool isLive = false}) {
    _polylineCoordinates = coords;
    setState(() {
      _polylines[const PolylineId('route')] = Polyline(
        polylineId: const PolylineId('route'),
        color: isLive
            ? const Color(0xFF32A1FF)
            : Colors.teal, // Navigation Blue or Planning Teal
        points: coords,
        width: isLive ? 10 : 6, // Thicker in navigation mode
      );
    });
  }

  Future<void> _startLiveNavigation() async {
    setState(() {
      _isNavigating = true;
      _isAutoFollowing = true;
    });

    // Instantly trigger navigation boot with the current location
    try {
      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      _onLocationUpdate(position);
    } catch (e) {
      debugPrint("Could not get initial live position: $e");
    }

    _positionStream?.cancel();
    _positionStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high, distanceFilter: 5),
    ).listen((geo.Position position) {
      _onLocationUpdate(position);
    });
  }

  void _onLocationUpdate(geo.Position position) {
    if (!_isNavigating) return;

    LatLng currentPos = LatLng(position.latitude, position.longitude);

    // 1. Update Marker & Camera
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user_nav');
      _markers.add(Marker(
        markerId: const MarkerId('user_nav'),
        position: currentPos,
        rotation: position.heading,
        anchor: const Offset(0.5, 0.5),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
      ));
    });

    if (_isAutoFollowing) {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
            target: currentPos,
            zoom: 19, // Deeper zoom for navigation
            tilt: 75, // Aggressive 3D tilt
            bearing: position.heading),
      ));
    }

    // Update route color to Navigation Blue
    _drawPolyline(_polylineCoordinates, isLive: true);

    // 2. Check for Rerouting (if more than 50m from nearest point on polyline)
    double minDistance = double.infinity;
    for (var coord in _polylineCoordinates) {
      double d = geo.Geolocator.distanceBetween(position.latitude,
          position.longitude, coord.latitude, coord.longitude);
      if (d < minDistance) minDistance = d;
    }

    if (minDistance > 50) {
      debugPrint("Off-route detected. Rerouting...");
      _setStartToCurrentLocation().then((_) => _startRouting());
      return;
    }

    // 3. Update Instructions
    _updateNavigationProgress(position);
  }

  void _updateNavigationProgress(geo.Position pos) {
    if (_routeSteps.isEmpty) return;

    // Find if we reached the next step
    var nextStep = _routeSteps[_currentStepIndex];

    if (_currentStepIndex < _routeSteps.length - 1) {
      var nextInstructionCoord = _polylineCoordinates[nextStep['to_index']];
      double dist = geo.Geolocator.distanceBetween(pos.latitude, pos.longitude,
          nextInstructionCoord.latitude, nextInstructionCoord.longitude);

      setState(() {
        _distanceToNextStep = dist;
        _currentInstruction =
            nextStep['instruction']['text'] ?? "Follow the route";
      });

      if (dist < 20) {
        // Reached step
        _currentStepIndex++;
      }
    } else {
      setState(() {
        _currentInstruction = "You have arrived!";
      });
    }
  }

  Future<void> _stopNavigation() async {
    _positionStream?.cancel();
    setState(() {
      _isNavigating = false;
      _polylines = {};
      _polylineCoordinates = [];
    });
  }

  LatLngBounds _getBounds(LatLng origin, LatLng dest) {
    double minLat =
        origin.latitude < dest.latitude ? origin.latitude : dest.latitude;
    double maxLat =
        origin.latitude > dest.latitude ? origin.latitude : dest.latitude;
    double minLng =
        origin.longitude < dest.longitude ? origin.longitude : dest.longitude;
    double maxLng =
        origin.longitude > dest.longitude ? origin.longitude : dest.longitude;
    return LatLngBounds(
        southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition:
              CameraPosition(target: _destinationLatLng, zoom: 15.0),
          markers: _markers,
          polylines: Set<Polyline>.of(_polylines.values),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onMapCreated: (c) {
            _mapController = c;
          },
          zoomControlsEnabled: false,
        ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _modeIcon(Icons.directions_car, 'drive'),
                const SizedBox(width: 8),
                _modeIcon(Icons.directions_walk, 'walk'),
                const SizedBox(width: 8),
                _modeIcon(Icons.directions_bike, 'bicycle'),
                const SizedBox(width: 8),
                _modeIcon(Icons.directions_bus, 'bus'),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: _SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    isLoading: _isLoading,
                    onChanged: _fetchSuggestions,
                    onClear: _clearSearch,
                  ),
                ),
                const SizedBox(width: 8),
                _MapIconButton(
                  icon: Icons.my_location,
                  onTap: () async {
                    await _setStartToCurrentLocation();
                    if (_startLatLng != null) {
                      _mapController?.animateCamera(
                          CameraUpdate.newLatLngZoom(_startLatLng!, 16));
                    }
                  },
                  tooltip: "Find My Location",
                ),
                const SizedBox(width: 8),
                _MapIconButton(
                  icon: Icons.directions_rounded,
                  onTap: _startRouting,
                  tooltip: "Calculate Route",
                ),
              ]),
            ),
            if (_showSuggestions)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (c, i) => _SuggestionTile(
                      description: _suggestions[i]['description'],
                      onTap: () => _goToPlace(_suggestions[i]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Positioned(
          bottom: 24,
          left: 12,
          right: 12,
          child: _NavigationOverlay(
            instruction: _currentInstruction,
            distanceToNext: _distanceToNextStep,
            totalDistance: _totalDistance,
            totalDuration: _totalDuration,
            isNavigating: _isNavigating,
            imageUrl: widget.imageUrl,
            title: widget.title,
            onStart: _startLiveNavigation,
            onStop: _stopNavigation,
          ),
        ),
      ]),
    );
  }

  Widget _modeIcon(IconData icon, String mode) {
    final selected = _selectedMode == mode;
    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? Colors.teal : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: selected ? Colors.white : Colors.blueGrey),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _positionStream?.cancel();
    super.dispose();
  }
}

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _MapIconButton({required this.icon, required this.onTap, this.tooltip});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? "",
          child: SizedBox(
              width: 48, height: 48, child: Icon(icon, color: Colors.blueGrey)),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar(
      {required this.controller,
      required this.focusNode,
      required this.isLoading,
      required this.onChanged,
      required this.onClear});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search destination...',
          prefixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.close), onPressed: onClear)
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String description;
  final VoidCallback onTap;
  const _SuggestionTile({required this.description, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.location_on, color: Colors.blueGrey),
      title: Text(description, style: const TextStyle(fontSize: 13)),
      onTap: onTap,
    );
  }
}

class _NavigationOverlay extends StatelessWidget {
  final String instruction;
  final double distanceToNext;
  final double totalDistance;
  final double totalDuration;
  final bool isNavigating;
  final String? imageUrl;
  final String title;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _NavigationOverlay({
    required this.instruction,
    required this.distanceToNext,
    required this.totalDistance,
    required this.totalDuration,
    required this.isNavigating,
    this.imageUrl,
    required this.title,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isNavigating)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10)
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.navigation, color: Colors.white, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(instruction,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text("${(distanceToNext).toStringAsFixed(0)}m remaining",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imageUrl!.startsWith('http')
                          ? Image.network(
                              imageUrl!,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const SizedBox(),
                            )
                          : const SizedBox(),
                    ),
                  ),
                Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.blueGrey, size: 20),
                    const SizedBox(width: 8),
                    Text("${(totalDuration / 60).toStringAsFixed(0)} min",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    const Icon(Icons.straighten,
                        color: Colors.blueGrey, size: 20),
                    const SizedBox(width: 8),
                    Text("${(totalDistance / 1000).toStringAsFixed(1)} km"),
                    const Spacer(),
                    if (!isNavigating)
                      ElevatedButton(
                        onPressed: onStart,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        child: const Text('Start',
                            style: TextStyle(color: Colors.white)),
                      )
                    else
                      IconButton(
                        onPressed: onStop,
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
