// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_camera/services/vr_optical_hand_tracker.dart';

CameraImage fixture({
  bool cluster = true,
  bool padded = false,
  bool biPlanar = false,
}) {
  const width = 64, height = 48;
  final stride = padded ? 80 : width;
  final chromaStride = padded ? 80 : (biPlanar ? width : width ~/ 2);
  final y = Uint8List(stride * height)..fillRange(0, stride * height, 120);
  final u = Uint8List(chromaStride * height ~/ 2)
    ..fillRange(0, chromaStride * height ~/ 2, 128);
  final v = Uint8List(chromaStride * height ~/ 2)
    ..fillRange(0, chromaStride * height ~/ 2, 128);
  if (cluster) {
    for (var row = 8; row < 16; row++) {
      for (var column = 16; column < 24; column++) {
        if (biPlanar) {
          u[row * chromaStride + column * 2] = 105;
          u[row * chromaStride + column * 2 + 1] = 153;
        } else {
          u[row * chromaStride + column] = 105;
          v[row * chromaStride + column] = 153;
        }
      }
    }
  }
  return CameraImage.fromPlatformData({
    'format': 35,
    'width': width,
    'height': height,
    'planes': [
      {'bytes': y, 'bytesPerRow': stride, 'bytesPerPixel': 1},
      {
        'bytes': u,
        'bytesPerRow': chromaStride,
        'bytesPerPixel': biPlanar ? 2 : 1,
      },
      if (!biPlanar)
        {'bytes': v, 'bytesPerRow': chromaStride, 'bytesPerPixel': 1},
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stride and interleaved chroma preserve the same estimated cluster', () {
    final frames = <VrHandLandmarkData>[];
    final tracker = VrOpticalHandTracker(
      minFrameIntervalMs: 0,
      onHandDetected: frames.add,
    );
    tracker.processFrame(fixture());
    tracker.processFrame(fixture(padded: true));
    tracker.processFrame(fixture(biPlanar: true, padded: true));
    expect(frames, hasLength(3));
    expect(frames[0].landmarks.first.x, frames[1].landmarks.first.x);
    expect(frames[0].landmarks.first.x, frames[2].landmarks.first.x);
    expect(
      frames.every((frame) => frame.isEstimated && frame.confidence < 0.5),
      isTrue,
    );
    expect(frames.first.landmarks, hasLength(21));
  });

  test('neutral walls produce no hand and loss is a single transition', () {
    var lost = 0;
    var detected = 0;
    final tracker = VrOpticalHandTracker(
      minFrameIntervalMs: 0,
      onHandDetected: (_) => detected++,
      onHandLost: () => lost++,
    );
    tracker.processFrame(fixture(cluster: false));
    expect(lost, 0);
    tracker.processFrame(fixture());
    tracker.processFrame(fixture(cluster: false));
    tracker.processFrame(fixture(cluster: false));
    expect(detected, 1);
    expect(lost, 1);
  });

  test(
    'monotonic throttle allows first frame and reset allows next immediately',
    () {
      var now = 0;
      final tracker = VrOpticalHandTracker(monotonicMicroseconds: () => now);
      tracker.processFrame(fixture());
      now = 1000;
      tracker.processFrame(fixture());
      now = 66000;
      tracker.processFrame(fixture());
      expect(tracker.processedFrames, 2);
      expect(tracker.droppedFrames, 1);
      tracker.reset();
      tracker.processFrame(fixture());
      expect(tracker.processedFrames, 3);
    },
  );
}
