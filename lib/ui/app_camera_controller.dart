import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img; // Alias para no confundir con el widget Image
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/utils/app_utilities.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/app_profile.dart';
import 'package:neom_core/domain/use_cases/camera_service.dart';
import 'package:neom_core/domain/use_cases/media_upload_service.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_core/utils/constants/core_constants.dart';
import 'package:neom_core/utils/enums/user_role.dart';
import 'package:neom_core/utils/neom_error_logger.dart';
import 'package:neom_core/utils/platform/core_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sint/sint.dart';

import 'camera_video_flip.dart';

class AppCameraController extends SintController implements AppCameraService {
  AppCameraController({UserService? userService})
    : _injectedUserService = userService;

  final UserService? _injectedUserService;
  UserService? get userServiceImpl {
    if (_injectedUserService != null) return _injectedUserService;
    if (Sint.isRegistered<UserService>()) return Sint.find<UserService>();
    return null;
  }

  AppProfile profile = AppProfile();

  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VoidCallback? videoPlayerListener;
  Timer? _maxDurationTimer;

  RxBool enableAudio = true.obs;
  int flashModeIndex = 0;
  Rx<Icon> flashIcon = const Icon(Icons.flash_off).obs;
  RxBool isRecording = false.obs;
  RxBool disposed = false.obs;
  RxBool isLoading = true.obs;
  bool mounted = false;
  bool _isClosed = false;

  static bool _hasSymlinkAncestor(String rawPath) {
    if (kIsWeb || rawPath.isEmpty) return false;
    var current = rawPath;
    final visited = <String>{};
    while (current.isNotEmpty && visited.add(current)) {
      if (current != '/tmp' &&
          current != '/var' &&
          current != '/etc' &&
          FileSystemEntity.isLinkSync(current)) {
        return true;
      }
      final parent = File(current).parent.path;
      if (parent == current) break;
      current = parent;
    }
    return false;
  }

  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;
  int get activePointers => _pointers;
  List<CameraDescription> cameras = [];

  void handlePointerDown() {
    _pointers = (_pointers + 1).clamp(0, 10);
  }

  void handlePointerUp() {
    _pointers = (_pointers - 1).clamp(0, 10);
  }

  void handlePointerCancel() {
    _pointers = (_pointers - 1).clamp(0, 10);
  }

  /// Normalizes a local tap position into `[0, 1]` camera sensor coordinates,
  /// returning `null` if viewport dimensions are zero or non-finite.
  static Offset? computeNormalizedTapPoint(
    Offset localPosition,
    Size viewportSize,
  ) {
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        !localPosition.dx.isFinite ||
        !localPosition.dy.isFinite) {
      return null;
    }
    return Offset(
      (localPosition.dx / viewportSize.width).clamp(0.0, 1.0),
      (localPosition.dy / viewportSize.height).clamp(0.0, 1.0),
    );
  }

  @override
  void onInit() {
    super.onInit();
    AppConfig.logger.t("AppCameraController onInit");
    mounted = true;
    final userSvc = userServiceImpl;
    if (userSvc != null) {
      profile = userSvc.profile;
    }

    try {
      initializeCameraController();

      onSetFlashModeButtonPressed(FlashMode.off);
    } catch (e, st) {
      NeomErrorLogger.recordError(
        e,
        st,
        module: 'neom_camera',
        operation: 'onInit',
      );
    }
  }

  @override
  void onClose() {
    if (_isClosed) return;
    _isClosed = true;
    mounted = false;
    _pointers = 0;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    final ctrl = controller;
    controller = null;
    if (ctrl != null) {
      unawaited(ctrl.dispose());
    }
    enableAudio.close();
    flashIcon.close();
    isRecording.close();
    disposed.close();
    isLoading.close();
    super.onClose();
  }

  @override
  Future<void> initializeCameraController() async {
    try {
      cameras = await availableCameras();

      if(cameras.isNotEmpty) {
        selectedCameraIndex = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (selectedCameraIndex == -1) selectedCameraIndex = 0;
        await _initializeCameraController(cameras[selectedCameraIndex]);
      }

      isLoading.value = false;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'initializeCameraController');
    }

  }

  @override
  Future<void> initializeFrontCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras.isNotEmpty) {
        // Find front camera specifically
        selectedCameraIndex = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        if (selectedCameraIndex == -1) {
          // Fallback to first camera if no front camera found
          selectedCameraIndex = 0;
          AppConfig.logger.w("Front camera not found, using default camera");
        }
        await _initializeCameraController(cameras[selectedCameraIndex]);
      }

      isLoading.value = false;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'initializeFrontCamera');
    }
  }

  void onSwitchCamera() {
    if (cameras.length < 2) return; // No hacer nada si solo hay 1 cámara

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras.length;
    final newCameraDescription = cameras[selectedCameraIndex];

    onNewCameraSelected(newCameraDescription);
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  @override
  Widget cameraPreviewWidget() {
    final activeController = controller;
    if (activeController == null || !activeController.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Listener(
      onPointerDown: (_) => handlePointerDown(),
      onPointerUp: (_) => handlePointerUp(),
      onPointerCancel: (_) => handlePointerCancel(),
      child: CameraPreview(
        activeController,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onTapDown: (TapDownDetails details) =>
                  onViewFinderTap(details, constraints),
            );
          },
        ),
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2 || !details.scale.isFinite) {
      return;
    }

    _currentScale = (_baseScale * details.scale).clamp(
      _minAvailableZoom,
      _maxAvailableZoom,
    );

    await controller!.setZoomLevel(_currentScale);
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget modeControlRowWidget() {
    final isVerified = userServiceImpl?.user.isVerified ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          icon: flashIcon.value,
          color: controller?.value.flashMode == FlashMode.off
              ? AppColor.mystic
              : AppColor.yellow,
          onPressed: controller != null ? onFlashModeButtonPressed : null,
        ),
        if (isVerified)
          IconButton(
            icon: Icon(enableAudio.value ? Icons.volume_up : Icons.volume_mute),
            color: enableAudio.value ? AppColor.mystic : AppColor.yellow,
            onPressed: controller != null ? onAudioModeButtonPressed : null,
          ),
      ],
    );
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    final Offset? offset = computeNormalizedTapPoint(
      details.localPosition,
      Size(constraints.maxWidth, constraints.maxHeight),
    );
    if (offset == null) return;
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
    // IMPORTANT: Dispose previous controller to release camera resources
    // This prevents "too many use cases" error on Android CameraX
    // when reinitializing camera for different purposes (photo vs video)
    if (controller != null) {
      AppConfig.logger.d("Disposing previous camera controller before reinitializing");
      try {
        await controller!.dispose();
      } catch (e, st) {
        NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: '_initializeCameraController.dispose');
      }
      controller = null;
    }

    // Use ResolutionPreset.high instead of max to avoid "too many use cases" error
    // on devices with limited camera surface combinations
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: isAudioEnabled,
      imageFormatGroup: !kIsWeb && (Platform.isIOS || Platform.isMacOS)
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.jpeg,
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
    } on CameraException catch (e, st) {
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
          NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: '_initializeCameraController');
          break;
      }
    }

    if (mounted) {
      disposed.value = false;
    }
  }

  @override
  void onTakePictureButtonPressed() {
    takePicture().then((File? file) {
      if (mounted && file != null) {
        imageFile = XFile(file.path);
      }

      if (file != null) {
        AppConfig.logger.i('Picture saved to ${file.path}');
        if (Sint.isRegistered<MediaUploadService>()) {
          Sint.find<MediaUploadService>().handleMedia(file);
        }
      }

    });
  }

  @override
  void onFlashModeButtonPressed() {

    FlashMode flashMode = FlashMode.off;
    if(flashModeIndex < 3) {
      flashModeIndex++;
    } else {
      flashModeIndex = 0;
    }
    switch(flashModeIndex) {
      case 0:
        flashIcon.value = const Icon(Icons.flash_off);
        flashMode = FlashMode.off;
        break;
      case 1:
        flashIcon.value = const Icon(Icons.flash_auto);
        flashMode = FlashMode.auto;
        break;
      case 2:
        flashIcon.value = const Icon(Icons.flash_on);
        flashMode = FlashMode.always;
        break;
      case 3:
        flashIcon.value = const Icon(Icons.highlight);
        flashMode = FlashMode.torch;
        break;
      case 4:
        break;
      case 5:
        break;
    }

    onSetFlashModeButtonPressed(flashMode);
  }

  @override
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

  @override
  void onVideoRecordButtonPressed() {
    if (isFrontCamera) {
      AppUtilities.showSnackBar(
        message:
            "Grabación de video no disponible en cámara frontal por el momento.",
      );
      return;
    }

    isRecording.value = true;
    startVideoRecording().then((_) {
      final activelyRecording = controller?.value.isRecordingVideo ?? false;
      if (!activelyRecording && mounted) {
        isRecording.value = false;
      }
      if (mounted) {
        update();
      }
    });
  }

  @override
  void onStopButtonPressed() {
    isRecording.value = false;

    stopVideoRecording().then((File? file) {
      if (mounted) {
        update();
      }



      if (file != null) {
        AppConfig.logger.i('Video recorded to ${file.path}');
        if (Sint.isRegistered<MediaUploadService>()) {
          Sint.find<MediaUploadService>().handleMedia(file);
        }
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

  @override
  void onPauseButtonPressed() {
    pauseVideoRecording().then((_) {
      if (mounted) {
        update();
      }
      AppUtilities.showSnackBar(message: 'Video recording paused');
    });
  }

  @override
  void onResumeButtonPressed() {
    resumeVideoRecording().then((_) {
      if (mounted) {
        update();
      }
      AppUtilities.showSnackBar(message: 'Video recording resumed');
    });
  }

  @override
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
      // Lock exposure before starting recording to prevent auto-adjustment
      // that causes darkening during recording on some devices
      try {
        await cameraController.setExposureMode(ExposureMode.locked);
        AppConfig.logger.d("Exposure locked for video recording");
      } catch (e, st) {
        NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'startVideoRecording.lockExposure');
      }

      await cameraController.startVideoRecording();

      final maxDurationInSeconds =
          userServiceImpl?.user.userRole == UserRole.subscriber
          ? CoreConstants.verifiedMaxVideoDurationInSeconds
          : CoreConstants.adminMaxVideoDurationInSeconds;
      final duration = Duration(seconds: maxDurationInSeconds);
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(duration, () {
        if (mounted &&
            controller == cameraController &&
            cameraController.value.isRecordingVideo) {
          onStopButtonPressed();
        }
      });
    } on CameraException catch (e, st) {
      isRecording.value = false;
      NeomErrorLogger.recordError(
        e,
        st,
        module: 'neom_camera',
        operation: 'startVideoRecording',
      );
      return;
    }
  }

  @override
  Future<File?> stopVideoRecording() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      // 1. Stop the recording
      XFile xfile = await cameraController.stopVideoRecording();
      if (!kIsWeb && _hasSymlinkAncestor(xfile.path)) {
        return null;
      }
      File videoFile = File(xfile.path);

      // Unlock exposure after recording is done
      try {
        await cameraController.setExposureMode(ExposureMode.auto);
        AppConfig.logger.d("Exposure unlocked after video recording");
      } catch (e, st) {
        NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'stopVideoRecording.unlockExposure');
      }

      // 2. Apply horizontal flip for front camera videos
      // This makes the recorded video match the preview (mirror effect like WhatsApp)
      if (!kIsWeb && isFrontCamera) {

        AppConfig.logger.i("Applying horizontal flip to front camera video...");

        try {
          // Generate output path for flipped video
          final directory = await getTemporaryDirectory();
          final String outputPath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_flipped.mp4';

          // Use easy_video_editor (via conditional IO helper) to flip horizontally
          final flippedPath = await flipCameraVideoHorizontally(
            videoPath: videoFile.path,
            outputPath: outputPath,
            onProgress: (progress) {
              AppConfig.logger.d('Flip progress: ${(progress * 100).toStringAsFixed(0)}%');
            },
          );

          if (flippedPath != null &&
              flippedPath.isNotEmpty &&
              !_hasSymlinkAncestor(flippedPath) &&
              File(flippedPath).existsSync()) {
            AppConfig.logger.i("Video flipped successfully: $flippedPath");

            // Delete original file to save space
            try {
              if (!_hasSymlinkAncestor(videoFile.path) &&
                  await videoFile.exists()) {
                await videoFile.delete();
              }
            } catch (e, st) {
              NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'stopVideoRecording.deleteOriginal');
            }

            videoFile = File(flippedPath);
          } else {
            AppConfig.logger.w("Flip failed, using original video");
          }
        } catch (e, st) {
          NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'stopVideoRecording.flipVideo');
          // If flip fails, return original video (still works, just not mirrored)
        }
      }

      return videoFile;
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'stopVideoRecording');
      return null;
    }
  }

  @override
  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'pauseVideoRecording');
      rethrow;
    }
  }

  @override
  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'resumeVideoRecording');
      rethrow;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'setFlashMode');
      rethrow;
    }
  }


  Future<void> setExposureMode(ExposureMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setExposureMode(mode);
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'setExposureMode');
      rethrow;
    }
  }

  @override
  Future<File?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      AppUtilities.showSnackBar(message: 'Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      if (!kIsWeb && _hasSymlinkAncestor(file.path)) {
        return null;
      }
      File savedFile = File(file.path);

      // --- LÓGICA DE CORRECCIÓN DE ESPEJO ---
      // Verificamos si la cámara actual es la frontal (solo IO nativo; en Web file.path es blob: URL)
      if (!kIsWeb && isFrontCamera) {

        AppConfig.logger.i("Procesando foto de cámara frontal (Flip Horizontal)...");

        // 1. Leemos los bytes de la imagen con tope anti-OOM (32 MiB)
        final imageBytes = await savedFile.readAsBytes();
        if (imageBytes.length <= 32 * 1024 * 1024) {
          // 2. Decodificamos la imagen usando la librería 'image'
          img.Image? originalImage = img.decodeImage(imageBytes);

          if (originalImage != null) {
            // 3. Volteamos horizontalmente (Flip)
            img.Image fixedImage = img.flipHorizontal(originalImage);

            // 4. Sobrescribimos el archivo original con la imagen corregida
            // Nota: encodeJpg es lo más común, ajusta si usas png
            await savedFile.writeAsBytes(img.encodeJpg(fixedImage));

            AppConfig.logger.i("Foto frontal corregida correctamente.");
          }
        }
      }
      return savedFile;
    } on CameraException catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'takePicture');
      return null;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_camera', operation: 'takePicture');
      return null;
    }
  }

  @override
  bool isInitialized() {
    return controller != null && controller!.value.isInitialized;
  }

  @override
  bool get isDisposed => disposed.value;

  int selectedCameraIndex = 0;

  CameraDescription? get _selectedCameraOrNull =>
      selectedCameraIndex >= 0 && selectedCameraIndex < cameras.length
      ? cameras[selectedCameraIndex]
      : null;

  // GETTER ÚTIL: Para saber si estamos en frontal
  bool get isFrontCamera {
    return _selectedCameraOrNull?.lensDirection == CameraLensDirection.front;
  }



}
