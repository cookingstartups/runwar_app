import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/cities_catalog.dart';
import '../services/database/cities_repository.dart';
import '../services/database/waitlist_repository.dart';

final citiesProvider = FutureProvider<List<CityEntry>>((ref) async {
  return CitiesRepository.instance.list();
});

final joinedCitySlugsProvider =
    FutureProvider.family<List<String>, String>((ref, userId) async {
  return WaitlistRepository.instance.joinedCitySlugs(userId);
});
