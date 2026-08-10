import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'us_places_local_datasource.dart';

enum DeviceLocationStatus {
  /// A real city and state came back from the device geocoder.
  resolved,
  serviceDisabled,
  permissionDenied,

  /// Coordinates arrived but no usable place name did — happens offline or in
  /// the middle of nowhere. The member types their city instead.
  unresolved,
}

class DeviceLocationResult {
  const DeviceLocationResult(this.status, {this.city, this.stateCode, this.countryCode});

  final DeviceLocationStatus status;
  final String? city;
  final String? stateCode;
  final String? countryCode;

  bool get isUsable =>
      status == DeviceLocationStatus.resolved && city != null && city!.isNotEmpty;
}

/// Seam over the platform location stack so the onboarding step can be widget
/// tested without a device.
abstract interface class DeviceLocationSource {
  Future<DeviceLocationResult> resolve();
}

class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  GeolocatorDeviceLocationSource({required UsPlacesLocalDataSource places})
    : _places = places;

  final UsPlacesLocalDataSource _places;

  @override
  Future<DeviceLocationResult> resolve() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DeviceLocationResult(DeviceLocationStatus.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const DeviceLocationResult(DeviceLocationStatus.permissionDenied);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );

    // City-level accuracy is all this flow needs, and all it should keep: the
    // coordinate is never stored, only the place name derived from it.
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (placemarks.isEmpty) {
      return const DeviceLocationResult(DeviceLocationStatus.unresolved);
    }

    final placemark = placemarks.first;
    final city = _firstNonEmpty([
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.subLocality,
      placemark.administrativeArea,
    ]);
    if (city == null) {
      return const DeviceLocationResult(DeviceLocationStatus.unresolved);
    }

    final countryCode = (placemark.isoCountryCode ?? '').toUpperCase();
    final stateCode = countryCode == 'US'
        ? await _places.stateCodeFor(placemark.administrativeArea ?? '')
        : null;

    return DeviceLocationResult(
      DeviceLocationStatus.resolved,
      city: city,
      stateCode: stateCode,
      countryCode: countryCode.isEmpty ? null : countryCode,
    );
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
