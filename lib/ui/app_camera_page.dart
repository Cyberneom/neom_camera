import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/theme/app_theme.dart';
import 'package:neom_commons/ui/widgets/app_circular_progress_indicator.dart';
import 'package:neom_commons/ui/widgets/appbar_child.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
import 'app_camera_controller.dart';

class AppCameraPage extends StatelessWidget {

  const AppCameraPage({super.key});


  @override
  Widget build(BuildContext context) {

    return GetBuilder<AppCameraController>(
      id: AppPageIdConstants.camera,
      init: AppCameraController(),
      builder: (controller) => Scaffold(
      appBar: AppBarChild(
        leadingWidget: IconButton(icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: AppTranslationConstants.newPost.tr, centerTitle: true,
      ),
      backgroundColor: AppColor.main50,
      body: SizedBox(
        child: Obx(()=> controller.isLoading.value ? AppCircularProgressIndicator() : Stack(
        alignment: Alignment.center,
        children: [
          (!controller.isDisposed) ? SizedBox(
            width: AppTheme.fullWidth(context),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50.0),
                bottomRight: Radius.circular(50.0),
              ),
              child: controller.cameraPreviewWidget(),),
          ) : const CircularProgressIndicator(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: controller.modeControlRowWidget(),
            )
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: GestureDetector(
                onTap: () {
                  if(controller.controller != null && controller.controller!.value.isInitialized && !controller.controller!.value.isRecordingVideo) {
                    controller.onTakePictureButtonPressed();
                  }
                },
                onLongPress: () {
                  if((controller.userServiceImpl.user.isVerified) && controller.controller != null
                      && controller.controller!.value.isInitialized && !controller.controller!.value.isRecordingVideo) {
                    controller.onVideoRecordButtonPressed();
                  }
                },
                onLongPressEnd: (details) {
                  if((controller.userServiceImpl.user.isVerified) && controller.controller != null
                      && controller.controller!.value.isInitialized && controller.controller!.value.isRecordingVideo) {
                    controller.onStopButtonPressed();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: controller.isRecording.value ? 90 : 80,
                  height: controller.isRecording.value ? 90 : 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: controller.isRecording.value ? AppColor.red : AppColor.lightGrey,
                  ),
                  child: controller.isRecording.value ? const Icon(Icons.stop, color: Colors.white, size: 45,) : null,
                ),
              ),
            ),
          ),
         ],),
        ),
      ),),
    );
  }

}
