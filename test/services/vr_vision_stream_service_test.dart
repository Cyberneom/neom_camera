// ignore_for_file: must_call_super

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_camera/services/vr_vision_stream_service.dart';

const camera = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

// CameraImage's legacy factory is convenient for synthetic stride fixtures.
// ignore: deprecated_member_use
CameraImage image() => CameraImage.fromPlatformData({
  'format': 35,
  'width': 2,
  'height': 2,
  'planes': [
    {'bytes': Uint8List(4), 'bytesPerRow': 2, 'bytesPerPixel': 1},
  ],
});

class FakeCamera extends CameraController {
  FakeCamera() : super(camera, ResolutionPreset.low);
  Completer<void>? initialization;
  bool failInitialization = false;
  bool failStop = false;
  int starts = 0;
  int disposals = 0;
  void Function(CameraImage)? callback;

  @override
  Future<void> initialize() async {
    await initialization?.future;
    if (failInitialization) throw StateError('initialize failed');
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<double> getMinZoomLevel() async => 1;
  @override
  Future<void> startImageStream(void Function(CameraImage) onAvailable) async {
    starts++;
    callback = onAvailable;
    value = value.copyWith(isStreamingImages: true);
  }

  @override
  Future<void> stopImageStream() async {
    if (failStop) throw StateError('stop failed');
    value = value.copyWith(isStreamingImages: false);
  }

  // No real plugin resources are allocated by this fake.
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native frames are capped without allocating a pending frame queue',
    () async {
      var now = 0;
      final native = FakeCamera();
      final service = VrVisionStreamService(
        camerasProvider: () async => [camera],
        controllerFactory: (_, _) => native,
        monotonicMicroseconds: () => now,
      );
      var received = 0;
      final subscription = service.onFrame.listen((_) => received++);
      expect(await service.start(), isTrue);
      for (var i = 0; i < 31; i++) {
        now = (i * 1000000 / 30).floor();
        native.callback!(image());
      }
      expect(received, 16); // first + 15 intervals over a second
      expect(service.publishedFrames, 16);
      expect(service.droppedFrames, 15);
      await subscription.cancel();
      now += 1000000;
      native.callback!(image());
      expect(received, 16);
      await service.close();
      expect(native.disposals, 1);
    },
  );

  test(
    'asynchronous analysis retains one frame and drops busy arrivals',
    () async {
      var now = 0;
      final native = FakeCamera();
      final service = VrVisionStreamService(
        camerasProvider: () async => [camera],
        controllerFactory: (_, _) => native,
        monotonicMicroseconds: () => now,
      );
      final inference = Completer<void>();
      var calls = 0;
      final subscription = service.listenForAnalysis((_) {
        calls++;
        return inference.future;
      });
      await service.start();
      for (var i = 0; i < 5; i++) {
        now = i * 100000;
        native.callback!(image());
      }
      expect(calls, 1);
      expect(service.analysisBusyDrops, 4);
      inference.complete();
      await Future<void>.delayed(Duration.zero);
      now += 100000;
      native.callback!(image());
      expect(calls, 2);
      await subscription.cancel();
      await service.close();
    },
  );

  test('stop cancels pending initialization and disposal still wins', () async {
    final native = FakeCamera()..initialization = Completer<void>();
    final service = VrVisionStreamService(
      camerasProvider: () async => [camera],
      controllerFactory: (_, _) => native,
    );
    final starting = service.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = service.stop();
    native.initialization!.complete();
    expect(await starting, isFalse);
    await stopping;
    expect(native.starts, 0);
    expect(native.disposals, 1);
    expect(service.controller, isNull);
    await service.close();
  });

  test(
    'initialization failure and stream-stop failure both release controller',
    () async {
      final failed = FakeCamera()..failInitialization = true;
      final service = VrVisionStreamService(
        camerasProvider: () async => [camera],
        controllerFactory: (_, _) => failed,
      );
      expect(await service.start(), isFalse);
      expect(failed.disposals, 1);
      await service.close();
      final native = FakeCamera()..failStop = true;
      final next = VrVisionStreamService(
        camerasProvider: () async => [camera],
        controllerFactory: (_, _) => native,
      );
      expect(await next.start(), isTrue);
      await next.close();
      expect(native.disposals, 1);
      expect(await next.start(), isFalse);
    },
  );

  test('simultaneous starts share one hardware controller', () async {
    final native = FakeCamera();
    var factories = 0;
    final service = VrVisionStreamService(
      camerasProvider: () async => [camera],
      controllerFactory: (_, _) {
        factories++;
        return native;
      },
    );
    expect(await Future.wait([service.start(), service.start()]), [true, true]);
    expect(factories, 1);
    expect(native.starts, 1);
    await service.close();
  });
}
