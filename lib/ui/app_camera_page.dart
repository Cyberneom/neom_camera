import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/theme/app_theme.dart';
import 'package:neom_commons/ui/widgets/app_circular_progress_indicator.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
import 'package:sint/sint.dart';

import 'app_camera_controller.dart';

class AppCameraPage extends StatelessWidget {
  const AppCameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SintBuilder<AppCameraController>(
      id: AppPageIdConstants.camera,
      init: AppCameraController(),
      builder: (controller) => Scaffold(
        appBar: SintAppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Sint.back(),
          ),
          title: AppTranslationConstants.camera.tr,
          centerTitle: true,
        ),
        backgroundColor: AppColor.scaffold,
        body: SizedBox(
          child: Obx(() => controller.isLoading.value
              ? const AppCircularProgressIndicator()
              : Stack(
            alignment: Alignment.center,
            children: [
              // VISTA PREVIA CÁMARA
              (!controller.isDisposed)
                  ? SizedBox(
                width: AppTheme.fullWidth(context),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(50.0),
                    bottomRight: Radius.circular(50.0),
                  ),
                  child: controller.cameraPreviewWidget(),
                ),
              )
                  : const CircularProgressIndicator(),

              // CONTROLES (Flash, Audio, SWITCH CAMERA)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 30.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Botón Flash existente
                      IconButton(
                        icon: controller.flashIcon.value,
                        color: controller.controller?.value.flashMode == FlashMode.off
                            ? AppColor.mystic
                            : AppColor.yellow,
                        onPressed: controller.controller != null
                            ? controller.onFlashModeButtonPressed
                            : null,
                      ),

                      // Espacio para el botón de disparo
                      const SizedBox(width: 80),

                      // NUEVO: Botón Cambiar Cámara
                      IconButton(
                        icon: const Icon(Icons.cameraswitch_outlined),
                        color: AppColor.mystic,
                        onPressed: controller.cameras.length > 1
                            ? controller.onSwitchCamera
                            : null,
                      ),
                    ],
                  ),
                ),
              ),

              // BOTÓN DE DISPARO (Obturador)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 30.0),
                  child: GestureDetector(
                    onTap: () {
                      if (controller.controller != null &&
                          controller.controller!.value.isInitialized &&
                          !controller.controller!.value.isRecordingVideo) {
                        controller.onTakePictureButtonPressed();
                      }
                    },
                    onLongPress: () {
                      if ((controller.userServiceImpl.user.isVerified) &&
                          controller.controller != null &&
                          controller.controller!.value.isInitialized &&
                          !controller.controller!.value.isRecordingVideo) {
                        controller.onVideoRecordButtonPressed();
                      }
                    },
                    onLongPressEnd: (details) {
                      if ((controller.userServiceImpl.user.isVerified) &&
                          controller.controller != null &&
                          controller.controller!.value.isInitialized &&
                          controller.controller!.value.isRecordingVideo) {
                        controller.onStopButtonPressed();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: controller.isRecording.value ? 90 : 80,
                      height: controller.isRecording.value ? 90 : 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: controller.isRecording.value
                            ? AppColor.red
                            : AppColor.lightGrey,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: controller.isRecording.value
                          ? const Icon(Icons.stop, color: Colors.white, size: 45)
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          )),
        ),
      ),
    );
  }
}
