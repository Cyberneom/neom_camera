import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Estimated hand pose. This fallback emits an articulated template around a
/// chroma cluster; it does not observe individual fingers or measure depth.
class VrHandLandmarkData {
  final List<vm.Vector3> landmarks;
  final bool isRightHand;
  final double confidence;
  final DateTime timestamp;
  final bool isEstimated;

  const VrHandLandmarkData({
    required this.landmarks,
    required this.isRightHand,
    this.confidence = 0.35,
    required this.timestamp,
    this.isEstimated = true,
  });
}

/// Bounded, allocation-light chroma heuristic for optional optical feedback.
/// This is not a MediaPipe/OpenXR detector: all 21 points are a pose template.
/// Use an actual native landmark model for finger gestures and safety-critical
/// interaction. No full-resolution RGB conversion or image copy is performed.
class VrOpticalHandTracker {
  bool _isProcessing = false;
  bool _hadHand = false;
  int? _lastProcessTimeUs;
  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? _monotonicMicroseconds;

  /// A separate analysis budget from the display refresh rate (default 15 Hz).
  final int minFrameIntervalMs;

  /// Maximum samples examined per frame, regardless of sensor resolution.
  final int maxSamples;
  void Function(VrHandLandmarkData frame)? onHandDetected;
  VoidCallback? onHandLost;

  int processedFrames = 0;
  int droppedFrames = 0;
  int lastAnalysisMicroseconds = 0;

  VrOpticalHandTracker({
    this.minFrameIntervalMs = 66,
    this.maxSamples = 3072,
    this.onHandDetected,
    this.onHandLost,
    @visibleForTesting int Function()? monotonicMicroseconds,
  }) : assert(minFrameIntervalMs >= 0),
       assert(maxSamples > 0),
       _monotonicMicroseconds = monotonicMicroseconds;

  void processFrame(CameraImage image) {
    final now = _monotonicMicroseconds?.call() ?? _clock.elapsedMicroseconds;
    final last = _lastProcessTimeUs;
    if (_isProcessing ||
        (last != null && now - last < minFrameIntervalMs * 1000)) {
      droppedFrames++;
      return;
    }
    _isProcessing = true;
    _lastProcessTimeUs = now;
    final analysisClock = Stopwatch()..start();
    try {
      final frame = _extractHandLandmarks(image);
      processedFrames++;
      if (frame != null) {
        _hadHand = true;
        onHandDetected?.call(frame);
      } else if (_hadHand) {
        _hadHand = false;
        // A room without a visible hand should not trigger UI/state work on
        // every camera frame. Only report the transition to lost.
        onHandLost?.call();
      }
    } catch (error) {
      debugPrint('[VrOpticalHandTracker] Frame analysis error: $error');
    } finally {
      lastAnalysisMicroseconds = analysisClock.elapsedMicroseconds;
      _isProcessing = false;
    }
  }

  /// Clears temporal state when switching camera, lens, or scene.
  void reset() {
    _hadHand = false;
    _lastProcessTimeUs = null;
  }

  VrHandLandmarkData? _extractHandLandmarks(CameraImage image) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0 || image.planes.isEmpty || maxSamples <= 0) {
      return null;
    }
    final yuv = image.format.group == ImageFormatGroup.yuv420;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    // Y-only images cannot distinguish skin from an ordinary illuminated wall.
    if ((!yuv && !bgra) || (yuv && image.planes.length < 2)) return null;
    final first = image.planes.first;
    final columns = math.max(
      1,
      math.min(
        maxSamples,
        math.min(width, math.sqrt(maxSamples * width / height).floor()),
      ),
    );
    final rows = math.max(1, math.min(height, maxSamples ~/ columns));
    int skinCount = 0;
    int sampledCount = 0;
    double sumX = 0;
    double sumY = 0;
    int minX = width;
    int maxX = 0;
    int minY = height;
    int maxY = 0;
    // Offset each sample into its cell. Neither row nor pixel strides can be
    // inferred from the image width (YUV chroma planes may be interleaved).
    for (var row = 0; row < rows; row++) {
      final y = ((row + 0.5) * height / rows).floor();
      for (var column = 0; column < columns; column++) {
        final x = ((column + 0.5) * width / columns).floor();
        int luminance;
        int cb;
        int cr;
        if (bgra) {
          final offset = y * first.bytesPerRow + x * (first.bytesPerPixel ?? 4);
          if (offset < 0 || offset + 2 >= first.bytes.length) continue;
          final blue = first.bytes[offset];
          final green = first.bytes[offset + 1];
          final red = first.bytes[offset + 2];
          luminance = (77 * red + 150 * green + 29 * blue) >> 8;
          cb = 128 + ((-43 * red - 85 * green + 128 * blue) >> 8);
          cr = 128 + ((128 * red - 107 * green - 21 * blue) >> 8);
        } else {
          final offset = y * first.bytesPerRow + x * (first.bytesPerPixel ?? 1);
          if (offset < 0 || offset >= first.bytes.length) continue;
          luminance = first.bytes[offset];
          final u = image.planes[1];
          final cx = x ~/ 2;
          final cy = y ~/ 2;
          if (image.planes.length >= 3) {
            final v = image.planes[2];
            final uOffset = cy * u.bytesPerRow + cx * (u.bytesPerPixel ?? 1);
            final vOffset = cy * v.bytesPerRow + cx * (v.bytesPerPixel ?? 1);
            if (uOffset < 0 ||
                uOffset >= u.bytes.length ||
                vOffset < 0 ||
                vOffset >= v.bytes.length) {
              continue;
            }
            cb = u.bytes[uOffset];
            cr = v.bytes[vOffset];
          } else {
            // iOS 420 bi-planar UV. NV21 has a different format and is rejected.
            final offset = cy * u.bytesPerRow + cx * (u.bytesPerPixel ?? 2);
            if (offset < 0 || offset + 1 >= u.bytes.length) continue;
            cb = u.bytes[offset];
            cr = u.bytes[offset + 1];
          }
        }
        sampledCount++;
        if (luminance < 40 ||
            luminance > 235 ||
            cb < 77 ||
            cb > 127 ||
            cr < 133 ||
            cr > 173) {
          continue;
        }
        skinCount++;
        sumX += x;
        sumY += y;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    if (sampledCount < 16 || skinCount < math.max(8, sampledCount ~/ 40)) {
      return null;
    }
    // Reject a near-full-frame skin-colored surface; this remains a heuristic,
    // not a calibrated skin, body, or obstacle detector.
    if (skinCount / sampledCount > 0.60 || maxX <= minX || maxY <= minY) {
      return null;
    }
    final centerX = sumX / skinCount / width;
    final centerY = sumY / skinCount / height;
    final estimatedZ = (0.75 - (maxX - minX) / width * 0.9).clamp(0.20, 0.85);
    final isRightHand = centerX > 0.5;
    return VrHandLandmarkData(
      landmarks: _buildArticulatedLandmarks(
        centerX,
        centerY,
        estimatedZ,
        isRightHand,
      ),
      isRightHand: isRightHand,
      timestamp: DateTime.now(),
    );
  }

  /// Builds 21 landmarks formatted according to MediaPipe standard.
  List<vm.Vector3> _buildArticulatedLandmarks(
    double cx,
    double cy,
    double cz,
    bool isRightHand,
  ) {
    final handSign = isRightHand ? 1.0 : -1.0;

    final landmarks = <vm.Vector3>[];

    // 0: Wrist
    landmarks.add(vm.Vector3(cx, cy + 0.10, cz));

    // 1-4: Thumb (CMC, MCP, IP, Tip)
    landmarks.add(vm.Vector3(cx + 0.03 * handSign, cy + 0.06, cz - 0.01));
    landmarks.add(vm.Vector3(cx + 0.05 * handSign, cy + 0.02, cz - 0.02));
    landmarks.add(vm.Vector3(cx + 0.07 * handSign, cy - 0.01, cz - 0.03));
    landmarks.add(vm.Vector3(cx + 0.09 * handSign, cy - 0.04, cz - 0.04));

    // 5-8: Index Finger (MCP, PIP, DIP, Tip)
    landmarks.add(vm.Vector3(cx + 0.02 * handSign, cy - 0.02, cz - 0.01));
    landmarks.add(vm.Vector3(cx + 0.025 * handSign, cy - 0.06, cz - 0.02));
    landmarks.add(vm.Vector3(cx + 0.028 * handSign, cy - 0.09, cz - 0.03));
    landmarks.add(vm.Vector3(cx + 0.030 * handSign, cy - 0.12, cz - 0.04));

    // 9-12: Middle Finger (MCP, PIP, DIP, Tip)
    landmarks.add(vm.Vector3(cx + 0.00 * handSign, cy - 0.025, cz - 0.01));
    landmarks.add(vm.Vector3(cx + 0.00 * handSign, cy - 0.07, cz - 0.025));
    landmarks.add(vm.Vector3(cx + 0.00 * handSign, cy - 0.10, cz - 0.035));
    landmarks.add(vm.Vector3(cx + 0.00 * handSign, cy - 0.14, cz - 0.045));

    // 13-16: Ring Finger (MCP, PIP, DIP, Tip)
    landmarks.add(vm.Vector3(cx - 0.02 * handSign, cy - 0.02, cz - 0.01));
    landmarks.add(vm.Vector3(cx - 0.025 * handSign, cy - 0.06, cz - 0.02));
    landmarks.add(vm.Vector3(cx - 0.028 * handSign, cy - 0.09, cz - 0.03));
    landmarks.add(vm.Vector3(cx - 0.030 * handSign, cy - 0.12, cz - 0.04));

    // 17-20: Pinky Finger (MCP, PIP, DIP, Tip)
    landmarks.add(vm.Vector3(cx - 0.04 * handSign, cy + 0.00, cz - 0.01));
    landmarks.add(vm.Vector3(cx - 0.05 * handSign, cy - 0.03, cz - 0.02));
    landmarks.add(vm.Vector3(cx - 0.055 * handSign, cy - 0.06, cz - 0.025));
    landmarks.add(vm.Vector3(cx - 0.060 * handSign, cy - 0.08, cz - 0.03));

    return landmarks;
  }
}
