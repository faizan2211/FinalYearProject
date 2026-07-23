import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place_model.dart';

class FavoritesManager {
  static const String _key = 'favorite_places';

  static Future<List<Place>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonStringList = prefs.getStringList(_key);
    if (jsonStringList == null) return [];

    return jsonStringList
        .map((jsonStr) => Place.fromJson(jsonDecode(jsonStr)))
        .toList();
  }

  static Future<bool> isFavorite(String placeName) async {
    final favorites = await getFavorites();
    return favorites.any((p) => p.name == placeName);
  }

  static Future<void> toggleFavorite(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    List<Place> favorites = await getFavorites();
    
    if (favorites.any((p) => p.name == place.name)) {
      favorites.removeWhere((p) => p.name == place.name);
    } else {
      favorites.add(place);
    }

    List<String> jsonStringList = favorites.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_key, jsonStringList);
  }
}
