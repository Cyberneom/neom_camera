import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neom_commons/core/data/implementations/user_controller.dart';
import 'package:neom_commons/core/domain/model/app_profile.dart';
import 'package:neom_commons/core/utils/app_utilities.dart';
import 'package:neom_commons/core/utils/constants/app_constants.dart';
import 'package:neom_commons/neom_commons.dart';
import 'package:video_player/video_player.dart';

import '../neom_posts.dart';
import '../posts/ui/add/post_upload_controller.dart';

class NeomCameraController extends GetxController {

  var logger = AppUtilities.logger;
  final userController = Get.find<UserController>();
  PostUploadController uploadController = Get.find<PostUploadController>();
  AppProfile profile = AppProfile();

  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;

  RxBool enableAudio = true.obs;
  int flashModeIndex = 0;
  Icon flashIcon = const Icon(Icons.flash_off);
  RxBool isRecording = false.obs;
  RxBool disposed = false.obs;
  RxBool isLoading = true.obs;
  bool mounted = false;

  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;
  List<CameraDescription> cameras = [];

  @override
  void onInit() {
    super.onInit();
    logger.t("PostUpload Controller Init");
    profile = userController.profile;

    try {
      initializeCameraController();

      onSetFlashModeButtonPressed(FlashMode.off);

      if (Get.isRegistered<PostUploadController>()) {
        uploadController = Get.find<PostUploadController>();
      } else {
        uploadController = PostUploadController();
        Get.put(uploadController);
      }
    } catch (e) {
      logger.e(e.toString());
    }

  }

  @override
  void onReady() {
    super.onReady();

    try {
      // initializeCameraController();
      ///DEPRECATED verifyVideosPerWeekLimit();
    } catch (e) {
      logger.e(e.toString());
    }
  }

  @override
  void onClose() {
    super.onClose();
    controller?.dispose();
  }

  Future<void> initializeCameraController() async {
    try {
      cameras = await availableCameras();
      final rearCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.back);
      controller = CameraController(rearCamera, ResolutionPreset.high);
      await controller?.initialize();
      isLoading.value = false;
    } catch (e) {
      AppUtilities.logger.e(e.toString());
    }

  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget cameraPreviewWidget() {
    return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapDown: (TapDownDetails details) =>
                      onViewFinderTap(details, constraints),
                );
              }),
        )
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await controller!.setZoomLevel(_currentScale);
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget modeControlRowWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          icon: flashIcon,
          color: controller?.value.flashMode == FlashMode.off
              ? AppColor.mystic : AppColor.yellow,
          onPressed: controller != null ? onFlashModeButtonPressed : null,
        ),
        if (uploadController.userController.user.isVerified) IconButton(
          icon: Icon(enableAudio.value ? Icons.volume_up : Icons.volume_mute),
          color: enableAudio.value ? AppColor.mystic : AppColor.yellow,
          onPressed: controller != null ? onAudioModeButtonPressed : null,
        ),
      ],
    );
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      return controller!.setDescription(cameraDescription);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future<void> _initializeCameraController(CameraDescription cameraDescription, {bool isAudioEnabled = true}) async {
    final CameraController cameraController = CameraController(cameraDescription,
      ResolutionPreset.high, enableAudio: isAudioEnabled, imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        update();
      }
      if (cameraController.value.hasError) {
        AppUtilities.showSnackBar(message: 'Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        cameraController.getMaxZoomLevel().then((double value) => _maxAvailableZoom = value),
        cameraController.getMinZoomLevel().then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          AppUtilities.showSnackBar(message: 'You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
          AppUtilities.showSnackBar(message: 'Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
        // iOS only
          AppUtilities.showSnackBar(message: 'Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          AppUtilities.showSnackBar(message: 'You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
        // iOS only
          AppUtilities.showSnackBar(message: 'Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
        // iOS only
          AppUtilities.showSnackBar(message: 'Audio access is restricted.');
          break;
        default:
          AppUtilities.logger.e(e.toString());
          break;
      }
    }

    if (mounted) {
      disposed.value = false;
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        imageFile = file;
        videoController?.dispose();
        videoController = null;
      }

      if (file != null) {
        AppUtilities.logger.i('Picture saved to ${file.path}');
        uploadController.handleImage(imageFile: file);
      }
    });
  }

  void onFlashModeButtonPressed() {

    FlashMode flashMode = FlashMode.off;
    if(flashModeIndex < 3) {
      flashModeIndex++;
    } else {
      flashModeIndex = 0;
    }
    switch(flashModeIndex) {
      case 0:
        flashIcon = const Icon(Icons.flash_off);
        flashMode = FlashMode.off;
        break;
      case 1:
        flashIcon = const Icon(Icons.flash_auto);
        flashMode = FlashMode.auto;
        break;
      case 2:
        flashIcon = const Icon(Icons.flash_on);
        flashMode = FlashMode.always;
        break;
      case 3:
        flashIcon = const Icon(Icons.highlight);
        flashMode = FlashMode.torch;
        break;
      case 4:
        break;
      case 5:
        break;
    }

    onSetFlashModeButtonPressed(flashMode);
  }


  void onAudioModeButtonPressed() {
    enableAudio.value = !enableAudio.value;

    if (controller != null) {
      _initializeCameraController(controller!.description, isAudioEnabled: enableAudio.value);
    }

    if (mounted) {
      update();
    }
  }

  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        update();
      }
    });
  }

  void onVideoRecordButtonPressed() {
    isRecording.value = true;

    startVideoRecording().then((_) {
      if (mounted) {
        update();
      }
    });
  }

  void onStopButtonPressed() {
    isRecording.value = false;

    stopVideoRecording().then((XFile? file) {
      if (mounted) {
        update();
      }

      if (file != null) {
        AppUtilities.logger.i('Video recorded to ${file.path}');
        uploadController.handleVideo(videoFile: file);
      }
    });
  }

  Future<void> onPausePreviewButtonPressed() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      AppUtilities.showSnackBar(message: 'Error: select a camera first.');
      return;
    }

    if (cameraController.value.isPreviewPaused) {
      await cameraController.resumePreview();
    } else {
      await cameraController.pausePreview();
    }

    if (mounted) {
      update();
    }
  }

  void onPauseButtonPressed() {
    pauseVideoRecording().then((_) {
      if (mounted) {
        update();
      }
      AppUtilities.showSnackBar(message: 'Video recording paused');
    });
  }

  void onResumeButtonPressed() {
    resumeVideoRecording().then((_) {
      if (mounted) {
        update();
      }
      AppUtilities.showSnackBar(message: 'Video recording resumed');
    });
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      AppUtilities.showSnackBar(message: 'Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController.startVideoRecording();

      int maxDurationInSeconds = uploadController.userController.user.userRole == UserRole.subscriber
          ? AppConstants.verifiedMaxVideoDurationInSeconds : AppConstants.adminMaxVideoDurationInSeconds;
      Duration duration = Duration(seconds: maxDurationInSeconds);
      Timer(duration, () async {
        if (cameraController.value.isRecordingVideo) {
          onStopButtonPressed();
        }
      });

    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      return;
    }
  }

  Future<XFile?> stopVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      return cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      return null;
    }
  }

  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      rethrow;
    }
  }

  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      rethrow;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      rethrow;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setExposureMode(mode);
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      rethrow;
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      AppUtilities.showSnackBar(message: 'Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      AppUtilities.logger.e(e.toString());
      return null;
    }
  }

}
