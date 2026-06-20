import 'package:adhan/adhan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/providers/settings_provider.dart';

class PrayerData {
  const PrayerData({
    required this.times,
    required this.coordinates,
    required this.city,
    required this.date,
  });

  final PrayerTimes times;
  final Coordinates coordinates;
  final String city;
  final DateTime date;

  Prayer get nextPrayer => times.nextPrayer();
  DateTime? get nextPrayerTime => times.timeForPrayer(nextPrayer);
}

final locationPermissionProvider = FutureProvider<bool>((ref) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
});

final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final hasPermission = await ref.watch(locationPermissionProvider.future);
  if (!hasPermission) return null;
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 15),
    );
  } catch (_) {
    return await Geolocator.getLastKnownPosition();
  }
});

final prayerTimesProvider = FutureProvider<PrayerData?>((ref) async {
  final settings = ref.watch(settingsProvider);
  Position? position;

  if (settings.locationLat != null && settings.locationLng != null) {
    // Use saved location
    position = Position(
      latitude: settings.locationLat!,
      longitude: settings.locationLng!,
      timestamp: DateTime.now(),
      accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0,
      altitudeAccuracy: 0, headingAccuracy: 0,
    );
  } else {
    position = await ref.watch(currentPositionProvider.future);
  }

  if (position == null) return null;

  final coordinates = Coordinates(position.latitude, position.longitude);
  final params = _calculationParams(settings.calculationMethod);
  params.madhab = Madhab.shafi;

  final times = PrayerTimes.today(coordinates, params);

  // Save location if we fetched it fresh
  if (settings.locationLat == null) {
    ref.read(settingsProvider.notifier).setLocation(
          position.latitude,
          position.longitude,
          settings.locationCity ?? 'Current Location',
        );
  }

  return PrayerData(
    times: times,
    coordinates: coordinates,
    city: settings.locationCity ?? 'Current Location',
    date: DateTime.now(),
  );
});

CalculationParameters _calculationParams(int method) {
  switch (method) {
    case 0: return CalculationMethod.muslimWorldLeague.getParameters();
    case 1: return CalculationMethod.egyptian.getParameters();
    case 2: return CalculationMethod.karachi.getParameters();
    case 3: return CalculationMethod.ummAlQura.getParameters();
    case 4: return CalculationMethod.dubai.getParameters();
    case 5: return CalculationMethod.moonsightingCommittee.getParameters();
    case 6: return CalculationMethod.northAmerica.getParameters();
    case 7: return CalculationMethod.kuwait.getParameters();
    case 8: return CalculationMethod.qatar.getParameters();
    case 9: return CalculationMethod.singapore.getParameters();
    default: return CalculationMethod.muslimWorldLeague.getParameters();
  }
}
