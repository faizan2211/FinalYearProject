import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const String baseUrl = 'https://mongoose-colonial-deceit.ngrok-free.dev';

  Future<bool> checkLocationService() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print("[LocationService Error] $e");
      return null;
    }
  }

  Future<String> getCityFromCoords(double lat, double lng) async {
    final url = Uri.parse('$baseUrl/detect-city/?lat=$lat&lng=$lng');
    try {
      final response = await http.get(
        url,
        headers: {
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['city'] ?? 'Lahore';
      }
    } catch (e) {
      print("[LocationService CityDetect Error] $e");
    }
    return 'Lahore'; 
  }

  Future<String> getCountryFromCoords(double lat, double lng) async {
    final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=10&addressdetails=1');
    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'geo_assistant_app'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['address']?['country'] ?? 'Pakistan';
      }
    } catch (e) {
      print("[LocationService CountryDetect Error] $e");
    }
    return 'Pakistan';
  }
}
