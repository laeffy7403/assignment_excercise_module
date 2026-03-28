import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

class LocationController extends ChangeNotifier {
  // Current location
  Position? _currentPosition;

  // Route tracking
  List<Map<String, double>> _routePoints = [];
  double _totalDistance = 0.0;

  // FIX #5: Speed smoothing — keep a rolling window of recent samples
  final List<double> _speedSamples = [];
  static const int _speedWindowSize = 5; // average over last 5 samples
  double _smoothedSpeed = 0.0;

  DateTime? _lastPositionTime;
  DateTime? _lastSpeedCalculation;

  // Tracking state
  bool _isTracking = false;
  StreamSubscription<Position>? _positionSubscription;

  // Status
  String? _error;

  // Getters
  Position? get currentPosition => _currentPosition;
  List<Map<String, double>> get routePoints => List.unmodifiable(_routePoints);
  double get totalDistance => _totalDistance;
  bool get isTracking => _isTracking;
  String? get error => _error;

  /// Get current position as LatLng for flutter_map
  LatLng? get currentLatLng {
    if (_currentPosition == null) return null;
    return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
  }

  /// Get route points as LatLng list for flutter_map polyline
  List<LatLng> get routeLatLngs {
    return _routePoints
        .map((point) => LatLng(point['latitude']!, point['longitude']!))
        .toList();
  }

  /// Initialize location services and request permissions
  Future<bool> initialize() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _error = 'Location services are disabled';
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _error = 'Location permission denied';
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _error = 'Location permissions are permanently denied';
        notifyListeners();
        return false;
      }

      return true;
    } catch (e) {
      _error = 'Failed to initialize location: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentPosition = position;
      notifyListeners();
      return position;
    } catch (e) {
      _error = 'Failed to get current location: $e';
      notifyListeners();
      return null;
    }
  }

  /// Start tracking location for route recording
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      // Get initial position
      final initialPosition = await getCurrentLocation();
      if (initialPosition == null) return;

      _lastPositionTime = DateTime.now();

      // Add initial point to route
      _routePoints.add({
        'latitude': initialPosition.latitude,
        'longitude': initialPosition.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });

      _lastSpeedCalculation = DateTime.now();

      // FIX #3 & #6: Lower distanceFilter so small movements register;
      // removed timeLimit (it caused stream errors on some devices)
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // update every 3 meters (was 5)
        ),
      ).listen(
        _onLocationUpdate,
        onError: _onLocationError,
      );

      _isTracking = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start tracking: $e';
      notifyListeners();
    }
  }

  /// Stop tracking location
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _smoothedSpeed = 0.0;
    _speedSamples.clear();
    notifyListeners();
  }

  /// Reset route and distance
  void resetRoute() {
    _routePoints.clear();
    _totalDistance = 0.0;
    _smoothedSpeed = 0.0;
    _speedSamples.clear();
    _lastSpeedCalculation = null;
    _lastPositionTime = null;
    notifyListeners();
  }

  /// Handle location updates
  void _onLocationUpdate(Position position) {
    final now = DateTime.now();

    if (_routePoints.isNotEmpty) {
      final lastPoint = _routePoints.last;
      final distanceMeters = Geolocator.distanceBetween(
        lastPoint['latitude']!,
        lastPoint['longitude']!,
        position.latitude,
        position.longitude,
      );

      // FIX #3: Only count distance if accuracy is reasonable
      // and movement is more than GPS noise (>1m)
      if (distanceMeters > 1.0 && position.accuracy < 30) {
        _totalDistance += distanceMeters / 1000.0;
      }

      // FIX #5: Robust speed calculation
      _updateSmoothedSpeed(position, distanceMeters, now);
    }

    _lastSpeedCalculation = now;

    // FIX #6: Always add new point so polyline updates continuously
    _routePoints.add({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': now.millisecondsSinceEpoch.toDouble(),
    });

    _currentPosition = position;
    notifyListeners(); // triggers Consumer rebuild → map redraws
  }

  /// FIX #5: Rolling-average speed to eliminate spikes
  void _updateSmoothedSpeed(Position position, double distanceMeters, DateTime now) {
    double newSample = 0.0;

    if (_lastSpeedCalculation != null) {
      final timeDiffSeconds =
          now.difference(_lastSpeedCalculation!).inMilliseconds / 1000.0;

      if (timeDiffSeconds > 0 && distanceMeters > 0) {
        // km/h from actual displacement
        final calculatedKmh =
            (distanceMeters / 1000.0) / (timeDiffSeconds / 3600.0);

        // GPS hardware speed (often smoother on good hardware)
        final gpsKmh = position.speed >= 0 ? position.speed * 3.6 : 0.0;

        // Use GPS speed if it's in a plausible range, otherwise use calculated
        if (gpsKmh > 0 && gpsKmh < 30) {
          // Blend: 60% GPS, 40% calculated — GPS is smoother
          newSample = (gpsKmh * 0.6) + (calculatedKmh * 0.4);
        } else {
          newSample = calculatedKmh;
        }

        // Hard cap: no one runs faster than 30 km/h
        newSample = newSample.clamp(0.0, 30.0);

        // Ignore tiny jitter — if displacement < 2m treat as stationary
        if (distanceMeters < 2.0) {
          newSample = 0.0;
        }
      }
    }

    // Rolling average
    _speedSamples.add(newSample);
    if (_speedSamples.length > _speedWindowSize) {
      _speedSamples.removeAt(0);
    }

    if (_speedSamples.isNotEmpty) {
      _smoothedSpeed =
          _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
    }
  }

  /// Handle location errors
  void _onLocationError(error) {
    _error = 'Location error: $error';
    notifyListeners();
  }

  /// Calculate distance between two points using LatLng
  static double calculateDistanceLatLng(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    ) /
        1000.0;
  }

  /// Calculate distance between two points
  static double calculateDistance(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
  }

  /// Get formatted coordinates
  String get formattedCoordinates {
    if (_currentPosition == null) return 'No location';
    return '${_currentPosition!.latitude.toStringAsFixed(6)}, '
        '${_currentPosition!.longitude.toStringAsFixed(6)}';
  }

  /// FIX #5: Use smoothed speed
  double? get currentSpeed {
    if (_isTracking) {
      return _smoothedSpeed;
    }
    return 0.0;
  }

  /// Get current altitude
  double? get currentAltitude {
    return _currentPosition?.altitude;
  }

  /// Get current accuracy
  double? get currentAccuracy {
    return _currentPosition?.accuracy;
  }

  /// Check if location has good accuracy (< 20 meters)
  bool get hasGoodAccuracy {
    return _currentPosition != null && _currentPosition!.accuracy < 20;
  }

  /// Calculate average speed for the route
  double getAverageSpeed() {
    if (_routePoints.length < 2) return 0.0;

    final firstPoint = _routePoints.first;
    final lastPoint = _routePoints.last;

    final timeDifferenceMs =
        lastPoint['timestamp']! - firstPoint['timestamp']!;
    final timeDifferenceHours = timeDifferenceMs / (1000 * 60 * 60);

    if (timeDifferenceHours == 0) return 0.0;

    return _totalDistance / timeDifferenceHours;
  }

  /// Get route as list of coordinates for map display
  List<Map<String, double>> getRouteForMap() {
    return _routePoints
        .map((point) => {
      'latitude': point['latitude']!,
      'longitude': point['longitude']!,
    })
        .toList();
  }

  /// Cleanup
  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}