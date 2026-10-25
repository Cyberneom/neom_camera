import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// A low-bandwidth analysis stream, independent of the VR display refresh rate.
class VrVisionStreamConfig {
  final ResolutionPreset resolution;

  /// Tries the selected rear camera's minimum zoom. Camera names do not expose
  /// physical focal lengths, so this does not guarantee an ultra-wide lens.
  final bool preferUltraWide;
  final int frameDecimation;

  /// Best-effort native capture request. The camera backend chooses support.
  /// Dart throttling alone cannot avoid native-to-Dart image buffer transfers.
  final int? captureFps;

  /// Maximum rate delivered to analysis subscribers. Preview should use the
  /// native camera texture rather than converting these images into bitmaps.
  final int analysisFps;

  const VrVisionStreamConfig({
    this.resolution = ResolutionPreset.low,
    this.preferUltraWide = true,
    this.frameDecimation = 1,
    this.captureFps = 15,
    this.analysisFps = 15,
  }) : assert(frameDecimation > 0),
       assert(captureFps == null || captureFps > 0),
       assert(analysisFps > 0);
}

/// Foreground camera analysis source. Camera ownership must be coordinated with
/// ARCore and other camera clients by the caller; opening this controller does
/// not enable concurrent cameras on hardware that lacks that capability.
class VrVisionStreamService {
  final VrVisionStreamConfig config;
  final Future<List<CameraDescription>> Function() _camerasProvider;
  final CameraController Function(CameraDescription, VrVisionStreamConfig)
  _controllerFactory;
  final int Function()? _monotonicMicroseconds;
  final Stopwatch _clock = Stopwatch()..start();

  CameraController? _controller;
  bool _isStreaming = false;
  bool _disposed = false;
  int _requestRevision = 0;
  int _frameCounter = 0;
  int? _lastPublishedUs;
  Future<void> _operations = Future<void>.value();
  Future<void>? _closeFuture;

  // Deliver immediately to unpaused listeners, avoiding an asynchronous queue
  // of full camera buffers. A subscriber doing asynchronous inference must drop
  // frames while busy. Cancel, rather than pause, subscriptions during absence:
  // Dart StreamSubscription.pause() is allowed to buffer events by design.
  final StreamController<CameraImage> _imageStreamController =
      StreamController<CameraImage>.broadcast(sync: true);

  int receivedFrames = 0;
  int publishedFrames = 0;
  int droppedFrames = 0;
  int analysisBusyDrops = 0;

  Stream<CameraImage> get onFrame => _imageStreamController.stream;
  bool get isStreaming => _isStreaming;
  CameraController? get controller => _controller;

  VrVisionStreamService({
    this.config = const VrVisionStreamConfig(),
    @visibleForTesting
    Future<List<CameraDescription>> Function()? camerasProvider,
    @visibleForTesting
    CameraController Function(CameraDescription, VrVisionStreamConfig)?
    controllerFactory,
    @visibleForTesting int Function()? monotonicMicroseconds,
  }) : _camerasProvider = camerasProvider ?? availableCameras,
       _controllerFactory = controllerFactory ?? _createController,
       _monotonicMicroseconds = monotonicMicroseconds;

  static CameraController _createController(
    CameraDescription camera,
    VrVisionStreamConfig config,
  ) => CameraController(
    camera,
    config.resolution,
    enableAudio: false,
    fps: config.captureFps,
    imageFormatGroup: ImageFormatGroup.yuv420,
  );

  int get _nowUs =>
      _monotonicMicroseconds?.call() ?? _clock.elapsedMicroseconds;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<bool> start() {
    if (_disposed) return Future<bool>.value(false);
    final revision = _requestRevision;
    return _enqueue(() => _start(revision));
  }

  Future<bool> _start(int revision) async {
    if (_disposed || revision != _requestRevision) return false;
    if (_isStreaming) return true;
    if (config.frameDecimation < 1 ||
        config.analysisFps < 1 ||
        (config.captureFps != null && config.captureFps! < 1)) {
      return false;
    }

    try {
      final cameras = await _camerasProvider();
      if (_disposed || revision != _requestRevision || cameras.isEmpty) {
        return false;
      }
      // Logical/numeric camera names cannot reliably identify ultra-wide lenses.
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = _controllerFactory(selected, config);
      _controller = camera;
      await camera.initialize();
      if (_disposed || revision != _requestRevision) {
        await _releaseController();
        return false;
      }
      if (config.preferUltraWide) {
        try {
          final minZoom = await camera.getMinZoomLevel();
          if (minZoom < 1.0) await camera.setZoomLevel(minZoom);
        } catch (error) {
          debugPrint(
            '[VrVisionStreamService] Minimum zoom unavailable: $error',
          );
        }
      }
      if (_disposed || revision != _requestRevision) {
        await _releaseController();
        return false;
      }
      _frameCounter = 0;
      _lastPublishedUs = null;
      await camera.startImageStream((image) => _onImage(image, revision));
      if (_disposed || revision != _requestRevision) {
        await _releaseController();
        return false;
      }
      _isStreaming = true;
      return true;
    } catch (error, stack) {
      debugPrint(
        '[VrVisionStreamService] Camera stream failed: $error\n$stack',
      );
      await _releaseController();
      return false;
    }
  }

  void _onImage(CameraImage image, int revision) {
    if (_disposed || revision != _requestRevision) return;
    receivedFrames++;
    _frameCounter++;
    final now = _nowUs;
    final last = _lastPublishedUs;
    if (!_imageStreamController.hasListener ||
        _frameCounter % config.frameDecimation != 0 ||
        (last != null && now - last < (1000000 ~/ config.analysisFps))) {
      droppedFrames++;
      return;
    }
    _lastPublishedUs = now;
    publishedFrames++;
    _imageStreamController.add(image);
  }

  /// Runs at most one asynchronous analyzer at a time. New frames are dropped
  /// while inference is in flight; they are never queued for later processing.
  /// Prefer this to an `async` callback passed directly to [onFrame.listen].
  StreamSubscription<CameraImage> listenForAnalysis(
    FutureOr<void> Function(CameraImage image) analyze, {
    void Function(Object error, StackTrace stack)? onError,
  }) {
    var busy = false;
    return onFrame.listen((image) {
      if (busy) {
        analysisBusyDrops++;
        return;
      }
      busy = true;
      unawaited(
        Future<void>.sync(() => analyze(image))
            .catchError((Object error, StackTrace stack) {
              if (onError != null) {
                onError(error, stack);
              } else {
                debugPrint('[VrVisionStreamService] Analysis failed: $error');
              }
            })
            .whenComplete(() => busy = false),
      );
    });
  }

  /// Cancels even a pending initialization, then releases the hardware lock.
  Future<void> stop() {
    _requestRevision++;
    _isStreaming = false;
    return _enqueue(_releaseController);
  }

  Future<void> _releaseController() async {
    final camera = _controller;
    _controller = null;
    _isStreaming = false;
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (error) {
      debugPrint('[VrVisionStreamService] Stop stream failed: $error');
    } finally {
      // Dispose is still required when stopping the image stream throws.
      try {
        await camera.dispose();
      } catch (error) {
        debugPrint('[VrVisionStreamService] Camera dispose failed: $error');
      }
    }
  }

  /// Await this when a new camera owner must acquire the device immediately.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _disposed = true;
    await stop();
    await _imageStreamController.close();
  }

  void dispose() => unawaited(close());
}
