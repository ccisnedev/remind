import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A point on the Earth's surface, in decimal degrees.
@immutable
final class GeoCoordinate {
  /// Creates a coordinate.
  ///
  /// [latitude] must be in −90…90 and [longitude] in −180…180.
  const GeoCoordinate(this.latitude, this.longitude)
      : assert(
          latitude >= -90 && latitude <= 90,
          'latitude must be in -90..90',
        ),
        assert(
          longitude >= -180 && longitude <= 180,
          'longitude must be in -180..180',
        );

  /// Degrees north of the equator; negative values are south.
  final double latitude;

  /// Degrees east of the prime meridian; negative values are west.
  final double longitude;

  /// Great-circle distance to [other], in metres.
  ///
  /// Uses the haversine formula on a spherical Earth. Accurate to roughly 0.5%,
  /// which is far below the precision of consumer GPS and of the geofence radii
  /// the platforms will accept, so the extra cost of an ellipsoidal model would
  /// buy nothing here.
  double distanceTo(GeoCoordinate other) {
    const earthRadiusMetres = 6371008.8;
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadiusMetres * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => '($latitude, $longitude)';
}

/// A circular area that a device can be inside of or outside of.
///
/// Both platforms model geofences as circles, so this does too. Note the hard
/// platform budgets: Android allows roughly 100 registered geofences per app
/// and iOS allows only 20 monitored regions in total, across the whole app.
/// Anything beyond that has to be swapped in and out by proximity, which is the
/// reconciler's problem rather than this type's.
@immutable
final class GeoRegion {
  /// Creates a circular region.
  const GeoRegion({
    required this.id,
    required this.center,
    required this.radiusMetres,
  }) : assert(radiusMetres > 0, 'radiusMetres must be positive');

  /// A stable identifier, used to correlate this region with the registration
  /// the operating system holds for it.
  final String id;

  /// The centre of the circle.
  final GeoCoordinate center;

  /// The radius in metres.
  ///
  /// Values below about 100 m are unreliable in practice: consumer GPS error,
  /// and the coarse cell/Wi-Fi positioning both platforms fall back on to save
  /// battery, routinely exceed that.
  final double radiusMetres;

  /// Whether [point] lies within this region.
  bool contains(GeoCoordinate point) =>
      center.distanceTo(point) <= radiusMetres;

  @override
  bool operator ==(Object other) =>
      other is GeoRegion &&
      other.id == id &&
      other.center == center &&
      other.radiusMetres == radiusMetres;

  @override
  int get hashCode => Object.hash(id, center, radiusMetres);

  @override
  String toString() => 'GeoRegion($id, $center, ${radiusMetres}m)';
}

/// The boundary crossing that fires a location trigger.
enum GeoEvent {
  /// The device moved from outside the region to inside it.
  enter,

  /// The device moved from inside the region to outside it.
  exit,

  /// The device stayed inside the region for a sustained period.
  ///
  /// Android supports this natively via its dwell transition. iOS does not, so
  /// an adapter has to emulate it by timing an [enter] and checking that no
  /// [exit] arrived in the meantime.
  dwell,
}
