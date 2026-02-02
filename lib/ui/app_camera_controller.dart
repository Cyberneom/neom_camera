import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sint/sint.dart';
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

class AppCameraController extends SintController implements AppCameraService {

  final userServiceImpl = Sint.find<UserService>();
  AppProfile profile = AppProfile();

  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VoidCallback? videoPlayerListener;

  RxBool enableAudio = true.obs;
  int flashModeIndex = 0;
  Rx<Icon> flashIcon = Icon(Icons.flash_off).obs;
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
    AppConfig.logger.t("AppCameraController onInit");
    profile = userServiceImpl.profile;

    try {
      initializeCameraController();

      onSetFlashModeButtonPressed(FlashMode.off);


    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

  }

  @override
  void onReady() {
    super.onReady();

    try {
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
  }

  @override
  void onClose() {
    super.onClose();
    controller?.dispose();
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
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

  }

  void onSwitchCamera() {
    if (cameras.length < 2) return; // No hacer nada si solo hay 1 cámara

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras.length;
    final newCameraDescription = cameras[selectedCameraIndex];

    onNewCameraSelected(newCameraDescription);
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
          icon: flashIcon.value,
          color: controller?.value.flashMode == FlashMode.off
              ? AppColor.mystic : AppColor.yellow,
          onPressed: controller != null ? onFlashModeButtonPressed : null,
        ),
        if (userServiceImpl.user.isVerified) IconButton(
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
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.max,
      enableAudio: isAudioEnabled,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
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
          AppConfig.logger.e(e.toString());
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
        Sint.find<MediaUploadService>().handleMedia(file);
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
      AppUtilities.showSnackBar(message: "Grabación de video no disponible en cámara frontal por el momento.");
      return;
    }

    isRecording.value = true;
    startVideoRecording().then((_) {
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
        Sint.find<MediaUploadService>().handleMedia(file);
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
      await cameraController.startVideoRecording();

      int maxDurationInSeconds = userServiceImpl.user.userRole == UserRole.subscriber
          ? CoreConstants.verifiedMaxVideoDurationInSeconds : CoreConstants.adminMaxVideoDurationInSeconds;
      Duration duration = Duration(seconds: maxDurationInSeconds);
      Timer(duration, () async {
        if (cameraController.value.isRecordingVideo) {
          onStopButtonPressed();
        }
      });

    } on CameraException catch (e) {
      AppConfig.logger.e(e.toString());
      return;
    }
  }

  @override
  Future<File?> stopVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      // 1. Detenemos la grabación normalmente
      XFile xfile = await cameraController.stopVideoRecording();
      File videoFile = File(xfile.path);

      ///Funcion para voltear video frontal pues se graba en espejo
      // 2. Verificamos si es cámara frontal para aplicar el efecto espejo
      // if (cameras.isNotEmpty &&
      //     cameras[selectedCameraIndex].lensDirection == CameraLensDirection.front) {
      //
      //   AppConfig.logger.i("Procesando video de cámara frontal (Flip Horizontal)... Esto puede tardar.");
      //
      //   // Activamos loading porque esto toma tiempo (depende de la duración del video)
      //   isLoading.value = true;
      //   update(); // Forzar actualización de UI para mostrar spinner
      //
      //   try {
      //
          // Generamos una ruta temporal para el video procesado
          // final directory = await getTemporaryDirectory();
          // final String outputPath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_flipped.mp4';

          // COMANDO FFMPEG:
          // -i [input]: Archivo original
          // -vf hflip: Filtro de video "Horizontal Flip"
          // -c:a copy: Copia el audio sin re-procesarlo (más rápido)
          // [output]: Archivo de salida
          // String command = '-i "${videoFile.path}" -vf hflip -c:a copy "$outputPath"';

          // // Ejecutamos el comando
          // await FFmpegKit.execute(command).then((session) async {
          //   final returnCode = await session.getReturnCode();
          //
          //   if (ReturnCode.isSuccess(returnCode)) {
          //     AppConfig.logger.i("Video volteado exitosamente.");
          //     // Si tuvo éxito, reemplazamos el archivo original con el procesado
          //     // Opcional: Borrar el original para ahorrar espacio
          //     if (await videoFile.exists()) {
          //       await videoFile.delete();
          //     }
          //     videoFile = File(outputPath);
          //   } else {
          //     AppConfig.logger.e("Error al voltear el video. Código: $returnCode");
          //     // Si falla, nos quedamos con el video original (invertido)
          //   }
          // });
      //   } catch (e) {
      //     AppConfig.logger.e("Excepción procesando video: $e");
      //   } finally {
      //     isLoading.value = false;
      //     update(); // Quitamos spinner
      //   }
      // }

      return videoFile;
    } on CameraException catch (e) {
      AppConfig.logger.e(e.toString());
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
    } on CameraException catch (e) {
      AppConfig.logger.e(e.toString());
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
    } on CameraException catch (e) {
      AppConfig.logger.e(e.toString());
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
      AppConfig.logger.e(e.toString());
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
      AppConfig.logger.e(e.toString());
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
      File savedFile = File(file.path);

      // --- LÓGICA DE CORRECCIÓN DE ESPEJO ---
      // Verificamos si la cámara actual es la frontal
      if (cameras.isNotEmpty &&
          cameras[selectedCameraIndex].lensDirection == CameraLensDirection.front) {

        AppConfig.logger.i("Procesando foto de cámara frontal (Flip Horizontal)...");

        // 1. Leemos los bytes de la imagen
        final imageBytes = await savedFile.readAsBytes();

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
      return savedFile;
    } on CameraException catch (e) {
      AppConfig.logger.e(e.toString());
      return null;
    } catch (e) {
      AppConfig.logger.e(e.toString());
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

  // GETTER ÚTIL: Para saber si estamos en frontal
  bool get isFrontCamera {
    if (cameras.isEmpty) return false;
    return cameras[selectedCameraIndex].lensDirection == CameraLensDirection.front;
  }



}
