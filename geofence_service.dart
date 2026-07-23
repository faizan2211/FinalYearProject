import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';
import 'location_service.dart';

class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final LocationService _locationService = LocationService();
  final NotificationService _notificationService = NotificationService();

  String? _lastDetectedCity;
  bool _isListening = false;

  void startListening(Function(String newCity)? onCityChanged) {
    if (_isListening) return;
    _isListening = true;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1000, 
      ),
    ).listen((Position position) async {
      String currentCity = await _locationService.getCityFromCoords(
        position.latitude,
        position.longitude,
      );

      if (_lastDetectedCity == null) {
        _lastDetectedCity = currentCity;
        await _notificationService.showNotification(
          "Welcome!",
          "Come explore $currentCity with us!",
        );
        if (onCityChanged != null) onCityChanged(currentCity);
      } else if (_lastDetectedCity!.toLowerCase() != currentCity.toLowerCase()) {
        _lastDetectedCity = currentCity;
        
        await _notificationService.showNotification(
          "Welcome!",
          "Come explore $currentCity with us!",
        );

        if (onCityChanged != null) onCityChanged(currentCity);
      }
    });
  }

  String? get lastDetectedCity => _lastDetectedCity;
}
