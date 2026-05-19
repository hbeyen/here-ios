import CoreLocation
import Foundation

/// GeoJSON Polygon body matching the shape `Here-Audio/lib/geofence.ts`
/// expects on the `POST /api/places` worker route. The single linear ring
/// must be closed (first coordinate equals last) and coordinates are
/// `[longitude, latitude]` per the GeoJSON spec.
struct GeoJSONPolygon: Encodable, Equatable {
  let type: String
  let coordinates: [[[Double]]]

  init(ring: [CLLocationCoordinate2D]) {
    self.type = "Polygon"
    self.coordinates = [ring.map { [$0.longitude, $0.latitude] }]
  }
}

enum Geofence {
  /// Approximates a circle of `radiusMeters` around `center` as a closed
  /// polygon with `segments` vertices (plus a duplicate closing vertex). 32
  /// segments looks visually round at city zoom and keeps the payload small.
  ///
  /// Uses a local flat-earth approximation — at city scale (radius < 1 km)
  /// the error vs. great-circle is well under a meter, which is far inside
  /// GPS noise on a phone.
  static func circlePolygon(
    center: CLLocationCoordinate2D,
    radiusMeters: Double,
    segments: Int = 32
  ) -> GeoJSONPolygon {
    let metersPerDegreeLat = 111_320.0
    let metersPerDegreeLng = max(
      111_320.0 * cos(center.latitude * .pi / 180.0),
      1.0 // avoid div-by-zero at the poles; we never broadcast there
    )

    let count = max(segments, 8)
    var ring: [CLLocationCoordinate2D] = []
    ring.reserveCapacity(count + 1)
    for i in 0..<count {
      let theta = (Double(i) / Double(count)) * 2.0 * .pi
      let dLat = (radiusMeters * cos(theta)) / metersPerDegreeLat
      let dLng = (radiusMeters * sin(theta)) / metersPerDegreeLng
      ring.append(
        CLLocationCoordinate2D(
          latitude: center.latitude + dLat,
          longitude: center.longitude + dLng
        )
      )
    }
    // Close the ring.
    if let first = ring.first {
      ring.append(first)
    }
    return GeoJSONPolygon(ring: ring)
  }
}
