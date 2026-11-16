import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Configuration for continuous background computer vision streaming.
class VrVisionStreamConfig {
  /// Target resolution preset for ML inference (low resolution = fast 60 FPS inference).
  final ResolutionPreset resolution;

  /// Whether to prefer the ultra-wide (0.5x) rear lens when available.
  final bool preferUltraWide;

  /// Frame decimation factor (e.g. 1 = every frame, 2 = every 2nd frame).
  final int frameDecimation;

  const VrVisionStreamConfig({
    this.resolution = ResolutionPreset.low, // 320x240 / 352x288
    this.preferUltraWide = true,
    this.frameDecimation = 1,
  });

  int get effectiveFrameDecimation => frameDecimation < 1 ? 1 : frameDecimation;
}

/// Headless background camera streaming service for VR Computer Vision & Hand Tracking.
///
/// Designed to run in the background without rendering a UI preview, feeding
/// continuous raw frames (CameraImage) directly to MediaPipe / TFLite pipelines.
class VrVisionStreamService {
  final VrVisionStreamConfig config;

  CameraController? _controller;
  bool _isStreaming = false;
  int _frameCounter = 0;

  /// Stream of raw camera frames ready for ML Hand Landmarker inference.
  final StreamController<CameraImage> _imageStreamController =
      StreamController<CameraImage>.broadcast();

  Stream<CameraImage> get onFrame => _imageStreamController.stream;
  bool get isStreaming => _isStreaming;
  CameraController? get controller => _controller;

  VrVisionStreamService({this.config = const VrVisionStreamConfig()});

  /// Initializes the optimal camera (Ultra-Wide 0.5x if available) and starts streaming.
  Future<bool> start() async {
    if (_isStreaming) return true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('[VrVisionStreamService] No cameras found on device');
        return false;
      }

      // 1. Select the best rear camera (preferring ultra-wide / back lens)
      CameraDescription selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // On Android Camera2, ultra-wide is often exposed with lower focal length or higher index
      for (final cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.back &&
            cam.name.toLowerCase().contains('wide')) {
          selectedCamera = cam;
          break;
        }
      }

      // 2. Initialize CameraController in Headless Mode (no audio)
      final createdController = CameraController(
        selectedCamera,
        config.resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _controller = createdController;

      await createdController.initialize();

      // 3. Set minimum zoom level (0.5x / 0.6x) to maximize FOV towards lap/chest
      if (config.preferUltraWide) {
        try {
          final minZoom = await createdController.getMinZoomLevel();
          if (minZoom.isFinite && minZoom > 0 && minZoom < 1.0) {
            await createdController.setZoomLevel(minZoom);
            debugPrint(
              '[VrVisionStreamService] Set Ultra-Wide Zoom: ${minZoom}x',
            );
          }
        } catch (e) {
          debugPrint('[VrVisionStreamService] Zoom setting skipped: $e');
        }
      }

      // 4. Start Low-Latency Frame Stream
      _frameCounter = 0;
      final decimation = config.effectiveFrameDecimation;
      await createdController.startImageStream((CameraImage image) {
        _frameCounter++;
        if (_frameCounter % decimation == 0) {
          if (!_imageStreamController.isClosed) {
            _imageStreamController.add(image);
          }
        }
      });

      _isStreaming = true;
      debugPrint(
        '[VrVisionStreamService] Continuous VR vision streaming active at ${config.resolution}',
      );
      return true;
    } catch (e, st) {
      debugPrint(
        '[VrVisionStreamService] Failed to start camera stream: $e\n$st',
      );
      try {
        await _controller?.dispose();
      } catch (_) {}
      _controller = null;
      _isStreaming = false;
      return false;
    }
  }

  /// Stops streaming and releases hardware camera locks.
  Future<void> stop() async {
    if (!_isStreaming && _controller == null) return;
    try {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
      await _controller?.dispose();
      debugPrint('[VrVisionStreamService] Vision streaming stopped');
    } catch (e) {
      debugPrint('[VrVisionStreamService] Error stopping camera: $e');
    } finally {
      _controller = null;
      _isStreaming = false;
    }
  }

  void dispose() {
    unawaited(stop());
    if (!_imageStreamController.isClosed) {
      unawaited(_imageStreamController.close());
    }
  }
}
