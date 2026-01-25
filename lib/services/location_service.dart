import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import 'auth_service.dart';
import 'localization_service.dart';

class LocationService {
  final SupabaseClient _client = SupabaseConfig.client;
  final AuthService _authService = AuthService();

  Future<bool> _ensurePermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return false;
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('${LocalizationService.t('location_permission')} error: $e');
      }
      return false;
    }
  }

  Future<(String? country, String? city)> _getCountryCity() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        return (null, null);
      }
      final hasPerm = await _ensurePermission();
      if (!hasPerm) return (null, null);
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      final placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final country = pm.country?.trim();
        final city = (pm.locality?.trim()?.isNotEmpty == true)
            ? pm.locality!.trim()
            : (pm.subAdministrativeArea?.trim());
        return (country, city);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Reverse geocode error: $e');
    }
    return (null, null);
  }

  Future<bool> updateUserProfileLocation() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return false;
      final (country, city) = await _getCountryCity();
      if ((country == null || country.isEmpty) &&
          (city == null || city.isEmpty)) {
        return false;
      }
      final updates = <String, dynamic>{};
      if (country != null && country.isNotEmpty) updates['country'] = country;
      if (city != null && city.isNotEmpty) updates['city'] = city;
      updates['updated_at'] = DateTime.now().toIso8601String();
      await _client.from('users').update(updates).eq('id', userId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Update profile location error: $e');
      return false;
    }
  }

  Future<bool> setManualLocation({
    required String country,
    String? city,
  }) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return false;
      final updates = <String, dynamic>{
        'country': country.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (city != null && city.trim().isNotEmpty) {
        updates['city'] = city.trim();
      }
      await _client.from('users').update(updates).eq('id', userId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Set manual location error: $e');
      return false;
    }
  }

  // Consent persistence: ask once policy
  static const String _consentKey = 'location_consent_choice';

  Future<bool?> getConsentChoice() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_consentKey)) return null; // not decided
    return prefs.getBool(_consentKey);
  }

  Future<void> setConsentChoice(bool consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, consent);
  }

  Future<String?> getStoredCountry() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return null;
      final row = await _client
          .from('users')
          .select('country')
          .eq('id', userId)
          .maybeSingle();
      final c = row != null ? row['country'] : null;
      if (c is String && c.trim().isNotEmpty) return c.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getStoredCity() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return null;
      final row = await _client
          .from('users')
          .select('city')
          .eq('id', userId)
          .maybeSingle();
      final c = row != null ? row['city'] : null;
      if (c is String && c.trim().isNotEmpty) return c.trim();
      return null;
    } catch (_) {
      return null;
    }
  }
}
