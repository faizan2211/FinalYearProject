import 'package:flutter/material.dart';
import 'package:geo_assistant/models/place_model.dart';
import 'package:geo_assistant/services/favorites_manager.dart';
import 'package:geo_assistant/MainPage/dynamic_place_info.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Place> favoritePlaces = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final places = await FavoritesManager.getFavorites();
    if (mounted) {
      setState(() {
        favoritePlaces = places;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite Places', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF091F2C),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFF091F2C),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : favoritePlaces.isEmpty
              ? const Center(
                  child: Text(
                    'No favorite places saved yet.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: favoritePlaces.length,
                  itemBuilder: (context, index) {
                    final place = favoritePlaces[index];
                    return GestureDetector(
                      onTap: () {
                        // Navigate to place details and refresh favorites when returning
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DynamicPlaceInfo(place: place),
                          ),
                        ).then((_) => _loadFavorites());
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                              ),
                              child: (place.imageUrl.isNotEmpty &&
                                      place.imageUrl.startsWith('http'))
                                  ? Image.network(
                                      place.imageUrl,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Container(
                                              width: 100,
                                              height: 100,
                                              color: Colors.grey[300]),
                                    )
                                  : Container(
                                      width: 100,
                                      height: 100,
                                      color: Colors.grey[300],
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    place.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${place.category} • ${place.city}",
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.star,
                                          color: Colors.orange, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        place.rating.toString(),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.favorite, color: Colors.red),
                              onPressed: () async {
                                await FavoritesManager.toggleFavorite(place);
                                _loadFavorites();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
