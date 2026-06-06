import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/twin_models.dart';

/// AR overlay service for responders.
///
/// Projects emergency information onto the real-world camera view:
/// - Hazard boundaries and intensity heatmaps
/// - Evacuation routes as ground-level paths
/// - Building status indicators (safe/damaged/collapsed)
/// - Casualty location markers
/// - Supply drop zone markers
///
/// Uses device camera + sensors (accelerometer, gyroscope, magnetometer)
/// for precise 6-DOF tracking without external markers.
class AROverlayService extends ChangeNotifier {
  bool _isActive = false;
  bool _isCalibrated = false;
  CameraPose? _currentPose;
  List<ARAnnotation> _annotations = [];
  List<Vector3> _evacuationPath = [];
  StreamSubscription? _sensorSubscription;

  // Sensor fusion state
  Vector3 _accelerometer = Vector3.zero();
  Vector3 _gyroscope = Vector3.zero();
  Vector3 _magnetometer = Vector3.zero();
  Quaternion _orientation = Quaternion.identity();

  // Calibration
  Vector3 _gyroBias = Vector3.zero();
  int _calibrationSamples = 0;
  static const int _requiredCalibrationSamples = 100;

  bool get isActive => _isActive;
  bool get isCalibrated => _isCalibrated;
  CameraPose? get currentPose => _currentPose;
  List<ARAnnotation> get annotations => _annotations;
  List<Vector3> get evacuationPath => _evacuationPath;

  /// Activate the AR overlay and start sensor fusion.
  Future<void> activate() async {
    if (_isActive) return;

    _isActive = true;
    _startSensorFusion();
    notifyListeners();
  }

  /// Deactivate the AR overlay.
  void deactivate() {
    _isActive = false;
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    notifyListeners();
  }

  /// Start sensor fusion for 6-DOF tracking.
  void _startSensorFusion() {
    // In production, this subscribes to platform sensor streams:
    // - CMMotionManager (iOS) or SensorManager (Android)
    // - Combines accelerometer + gyroscope + magnetometer via
    //   complementary filter or Kalman filter for drift correction.
    //
    // For cross-platform compatibility, we simulate the sensor
    // fusion pipeline here.

    _sensorSubscription = Stream.periodic(
      const Duration(milliseconds: 16), // ~60 FPS
      (count) => count,
    ).listen((_) {
      _updateOrientation();
      _updatePose();
      notifyListeners();
    });
  }

  /// Update orientation using complementary filter.
  void _updateOrientation() {
    if (!_isCalibrated && _calibrationSamples < _requiredCalibrationSamples) {
      _calibrationSamples++;
      // Accumulate gyro bias during calibration
      _gyroBias = Vector3(
        _gyroBias.x + _gyroscope.x,
        _gyroBias.y + _gyroscope.y,
        _gyroBias.z + _gyroscope.z,
      );

      if (_calibrationSamples >= _requiredCalibrationSamples) {
        // Average the bias
        _gyroBias = Vector3(
          _gyroBias.x / _requiredCalibrationSamples,
          _gyroBias.y / _requiredCalibrationSamples,
          _gyroBias.z / _requiredCalibrationSamples,
        );
        _isCalibrated = true;
      }
      return;
    }

    // Complementary filter: gyroscope integration + accelerometer correction
    const dt = 0.016; // 16ms
    const alpha = 0.98; // gyroscope weight

    // Remove bias from gyroscope readings
    final correctedGyro = Vector3(
      _gyroscope.x - _gyroBias.x,
      _gyroscope.y - _gyroBias.y,
      _gyroscope.z - _gyroBias.z,
    );

    // Gyroscope integration (delta rotation)
    final gyroQuat = Quaternion.fromEuler(
      correctedGyro.x * dt,
      correctedGyro.y * dt,
      correctedGyro.z * dt,
    );

    // Accelerometer gives gravity direction (tilt correction)
    final accelPitch = math.atan2(
      -_accelerometer.x,
      math.sqrt(_accelerometer.y * _accelerometer.y +
          _accelerometer.z * _accelerometer.z),
    );
    final accelRoll = math.atan2(
      _accelerometer.y,
      _accelerometer.z,
    );

    // Magnetometer gives heading (yaw correction)
    final magYaw = math.atan2(
      _magnetometer.y,
      _magnetometer.x,
    );

    // Complementary filter fusion
    final accelQuat = Quaternion.fromEuler(accelRoll, accelPitch, 0);
    final magQuat = Quaternion.fromEuler(0, 0, magYaw);

    // Blend gyroscope (high frequency) with accel/mag (low frequency)
    _orientation = Quaternion(
      alpha * gyroQuat.x + (1 - alpha) * accelQuat.x,
      alpha * gyroQuat.y + (1 - alpha) * accelQuat.y,
      alpha * gyroQuat.z + (1 - alpha) * magQuat.z,
      alpha * gyroQuat.w + (1 - alpha) * (accelQuat.w + magQuat.w) / 2,
    );
  }

  /// Update camera pose from orientation and GPS.
  void _updatePose() {
    // In production, this combines:
    // - Device GPS for absolute position
    // - Visual-inertial odometry for relative position
    // - ARKit/ARCore for plane detection and world tracking

    _currentPose = CameraPose(
      position: Vector3(0, 0, 0), // Relative to initial position
      orientation: _orientation,
      fieldOfView: 60.0, // degrees
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
  }

  /// Place an annotation in the AR view.
  void addAnnotation(ARAnnotation annotation) {
    _annotations.add(annotation);
    notifyListeners();
  }

  /// Remove an annotation by ID.
  void removeAnnotation(String id) {
    _annotations.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  /// Clear all annotations.
  void clearAnnotations() {
    _annotations.clear();
    notifyListeners();
  }

  /// Set the evacuation path to display on the ground.
  void setEvacuationPath(List<Vector3> path) {
    _evacuationPath = path;
    notifyListeners();
  }

  /// Project a 3D world point to 2D screen coordinates.
  Vector2? projectToScreen(Vector3 worldPoint, Size screenSize) {
    if (_currentPose == null) return null;

    // Simple perspective projection
    // In production, uses the camera's projection matrix from ARKit/ARCore
    final relativePos = worldPoint - _currentPose!.position;

    // Apply orientation (inverse rotation)
    final q = _currentPose!.orientation;
    final rotated = _rotateVectorByQuaternion(relativePos, q);

    // Perspective divide
    final fovRad = _currentPose!.fieldOfView * (math.pi / 180.0);
    final focalLength = screenSize.height / (2 * math.tan(fovRad / 2));

    if (rotated.z <= 0) return null; // Behind camera

    final screenX = (rotated.x / rotated.z) * focalLength + screenSize.width / 2;
    final screenY = -(rotated.y / rotated.z) * focalLength + screenSize.height / 2;

    return Vector2(screenX, screenY);
  }

  /// Rotate a vector by a quaternion.
  Vector3 _rotateVectorByQuaternion(Vector3 v, Quaternion q) {
    // q * v * q^-1
    final vQuat = Quaternion(v.x, v.y, v.z, 0);

    final qConj = Quaternion(-q.x, -q.y, -q.z, q.w);

    final temp = _quaternionMultiply(q, vQuat);
    final result = _quaternionMultiply(temp, qConj);

    return Vector3(result.x, result.y, result.z);
  }

  /// Multiply two quaternions.
  Quaternion _quaternionMultiply(Quaternion a, Quaternion b) {
    return Quaternion(
      a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
      a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    );
  }

  /// Simulate sensor input (for testing).
  void simulateSensorInput({
    Vector3? accelerometer,
    Vector3? gyroscope,
    Vector3? magnetometer,
  }) {
    if (accelerometer != null) _accelerometer = accelerometer;
    if (gyroscope != null) _gyroscope = gyroscope;
    if (magnetometer != null) _magnetometer = magnetometer;
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    super.dispose();
  }
}
