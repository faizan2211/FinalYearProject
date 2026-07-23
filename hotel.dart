import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geo_assistant/MainPage/home.dart';
import 'package:geo_assistant/Religious/religious.dart';
import 'package:geo_assistant/Famousplaces/famousplaces.dart';
import 'package:geo_assistant/shoppingmalls/malls.dart';
import 'package:geo_assistant/LogoutPage/logout.dart';
import 'package:geo_assistant/models/place_model.dart';
import 'package:geo_assistant/services/location_service.dart';
import 'package:geo_assistant/services/geofence_service.dart';
import 'package:geo_assistant/MainPage/dynamic_place_info.dart';
import 'package:geo_assistant/hotelInfo/awari.dart';
import 'package:geo_assistant/hotelInfo/four.dart';
import 'package:geo_assistant/hotelInfo/heritage.dart';
import 'package:geo_assistant/hotelInfo/indigo.dart';
import 'package:geo_assistant/hotelInfo/pc_info.dart';
import 'package:geo_assistant/hotelInfo/ramada.dart';
import 'package:geo_assistant/hotelInfo/crownhotel.dart';
import 'package:geo_assistant/hotelInfo/grandmillennium.dart';
import 'package:geo_assistant/hotelInfo/hotelone.dart';
import 'package:geo_assistant/hotelInfo/lahorecontinental.dart';
import 'package:geo_assistant/hotelInfo/smarthotel.dart';
import 'package:geo_assistant/hotelInfo/bestwestern.dart';
import 'package:geo_assistant/hotelInfo/falettisgrand.dart';
import 'package:geo_assistant/hotelInfo/falettis.dart';
import 'package:geo_assistant/hotelInfo/goldpine.dart';
import 'package:geo_assistant/hotelInfo/hotel1.dart';
import 'package:geo_assistant/hotelInfo/lahorec.dart';
import 'package:geo_assistant/hotelInfo/lawrence.dart';
import 'package:geo_assistant/hotelInfo/luxusgrand.dart';
import 'package:geo_assistant/hotelInfo/ninetree.dart';
import 'package:geo_assistant/hotelInfo/nishat.dart';
import 'package:geo_assistant/hotelInfo/panoramic.dart';
import 'package:geo_assistant/hotelInfo/premierinn.dart';
import 'package:geo_assistant/hotelInfo/rosepalace.dart';
import 'package:geo_assistant/hotelInfo/royals.dart';
import 'package:geo_assistant/hotelInfo/royauteluxury.dart';
import 'package:geo_assistant/hotelInfo/royaute.dart';
import 'package:geo_assistant/hotelInfo/residency.dart';

class Hotel extends StatefulWidget {
  const Hotel({super.key});

  @override
  _HotelState createState() => _HotelState();
}

class _HotelState extends State<Hotel> {
  final ScrollController _scrollController = ScrollController();

  String _detectedCity = 'Lahore';
  bool _gpsEnabled = true;
  bool _permissionGranted = true;
  bool _isLoading = true;
  List<Place> _hotels = [];
  bool _showAllHotels = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    setState(() {
      _isLoading = true;
    });

    final locService = LocationService();

    bool serviceEnabled = await locService.checkLocationService();
    if (!serviceEnabled) {
      setState(() {
        _gpsEnabled = false;
        _isLoading = false;
      });
      return;
    }

    var permission = await locService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await locService.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _permissionGranted = false;
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _permissionGranted = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _gpsEnabled = true;
      _permissionGranted = true;
    });

    final pos = await locService.getCurrentPosition();
    if (pos != null) {
      final city =
          await locService.getCityFromCoords(pos.latitude, pos.longitude);
      setState(() {
        _detectedCity = city;
      });
    }

    await _fetchHotels();

    GeofenceService().startListening((newCity) {
      if (mounted) {
        setState(() {
          _detectedCity = newCity;
        });
        _fetchHotels();
      }
    });
  }

  Future<void> _fetchHotels() async {
    try {
      final url = Uri.parse(
          '${LocationService.baseUrl}/places/?city=$_detectedCity&category=Hotel');
      final response = await http.get(
        url,
        headers: {
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _hotels = data.map((x) => Place.fromJson(x)).toList();
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Failed to load hotels");
      }
    } catch (e) {
      print("[Fetch Hotels Error] $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget getInfoPage(Place place) {
    return DynamicPlaceInfo(place: place);
  }

  Widget _buildGpsCard(double screenWidth) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Colors.indigoAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.location_off, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                "GPS Access Required",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "To discover the top-rated hotels, restaurants, and tourist attractions in your current city, please enable Location Services and allow GPS access.",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () async {
              final locService = LocationService();
              bool serviceEnabled = await locService.checkLocationService();
              if (!serviceEnabled) {
                await locService.openLocationSettings();
              } else {
                await _initLocation();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5DD6FF),
              foregroundColor: const Color(0xFF091F2C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              "Enable GPS / Allow Access",
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF091F2C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelsGrid(double screenWidth) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: CircularProgressIndicator(color: Colors.blueGrey),
        ),
      );
    }

    if (!_gpsEnabled || !_permissionGranted) {
      return _buildGpsCard(screenWidth);
    }

    if (_hotels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                "No top-rated hotels found in $_detectedCity.",
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayList = _showAllHotels ? _hotels : _hotels.take(7).toList();

    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          children: displayList.map((hotel) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            width: screenWidth > 500 ? screenWidth * 0.38 : screenWidth * 0.8,
            height: screenWidth * 0.38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                (hotel.imageUrl.isNotEmpty && hotel.imageUrl.startsWith('http'))
                    ? Image.network(
                        hotel.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[350],
                            child: const Icon(Icons.image_not_supported,
                                size: 80, color: Colors.grey),
                          );
                        },
                      )
                    : Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.grey[350],
                        child: const Icon(Icons.image_not_supported,
                            size: 80, color: Colors.grey),
                      ),
                Positioned(
                  bottom: 15,
                  left: 15,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => getInfoPage(hotel),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blueGrey),
                        borderRadius: BorderRadius.circular(59),
                        color: const Color.fromRGBO(77, 86, 82, 1.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Text(
                        hotel.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: screenWidth < 350
                              ? 15
                              : screenWidth < 500
                                  ? 16
                                  : screenWidth < 700
                                      ? 17
                                      : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 15,
                  right: 15,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          "${hotel.rating}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
    if (!_showAllHotels && _hotels.length > 7)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _showAllHotels = true;
            });
          },
          icon: const Icon(Icons.expand_more, color: Color(0xFF091F2C)),
          label: const Text(
            "View More Hotels",
            style: TextStyle(color: Color(0xFF091F2C), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5DD6FF),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotels'),
        backgroundColor: const Color(0xFF091F2C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.blueGrey),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogoutPage()),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF091F2C),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: screenHeight * 0.1),
                Text(
                  'Explore',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.04,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _detectedCity,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.065,
                      ),
                    ),
                    Text(
                      "$_detectedCity, Pakistan",
                      style: TextStyle(
                        height: screenHeight * 0.002,
                        fontSize: screenWidth * 0.04,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.12),
                Center(
                  child: SizedBox(
                    width: screenWidth > 600 ? 600 : screenWidth * 0.9,
                    child: TextField(
                      onSubmitted: (value) async {
                        if (value.trim().isNotEmpty) {
                          try {
                            final url = Uri.parse(
                                '${LocationService.baseUrl}/places/?city=$_detectedCity');
                            final response = await http.get(url, headers: {
                              'ngrok-skip-browser-warning': 'true'
                            });
                            if (response.statusCode == 200) {
                              final List<dynamic> data =
                                  json.decode(response.body);
                              final allPlaces =
                                  data.map((x) => Place.fromJson(x)).toList();
                              final place = allPlaces.firstWhere((p) => p.name
                                  .toLowerCase()
                                  .contains(value.toLowerCase().trim()));
                              if (context.mounted) {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            getInfoPage(place)));
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Place not found")),
                              );
                            }
                          }
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Find Places',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF5DD6FF), width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF5DD6FF), width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 35),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const Home()),
                          );
                        },
                        child: _categoryItem(
                          screenWidth,
                          "Food",
                          const Color(0xFF5DD6FF),
                          const Color(0xFF091F2C),
                          16,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const Hotel()),
                          );
                        },
                        child: _categoryItem(
                          screenWidth,
                          "Stay",
                          const Color(0xFF5DD6FF),
                          const Color(0xFF091F2C),
                          16,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const malls()),
                          );
                        },
                        child: _categoryItem(
                          screenWidth,
                          "Shopping",
                          const Color(0xFF5DD6FF),
                          const Color(0xFF091F2C),
                          16,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FamousPlaces(),
                            ),
                          );
                        },
                        child: _categoryItem(
                          screenWidth,
                          "Famous Places",
                          const Color(0xFF5DD6FF),
                          const Color(0xFF091F2C),
                          16,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const Religious(),
                            ),
                          );
                        },
                        child: _categoryItem(
                          screenWidth,
                          "Religious Places",
                          const Color(0xFF5DD6FF),
                          const Color(0xFF091F2C),
                          16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
                Text(
                  'Popular Hotel',
                  style: TextStyle(
                    fontSize: screenWidth * 0.04,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),
                _buildHotelsGrid(screenWidth),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryItem(
    double screenWidth,
    String title,
    Color bgColor,
    Color textColor,
    double borderRadius,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: screenWidth > 600 ? screenWidth * 0.17 : screenWidth * 0.27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: Colors.transparent,
          border: Border.all(color: bgColor, width: 2),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: bgColor,
              fontSize: screenWidth < 350 ? 14 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
