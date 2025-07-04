
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/commons/ui/theme/app_color.dart';
import 'package:neom_commons/commons/ui/theme/app_theme.dart';
import 'package:neom_commons/commons/ui/widgets/app_circular_progress_indicator.dart';
import 'package:neom_commons/commons/ui/widgets/appbar_child.dart';
import 'package:neom_commons/commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/commons/utils/constants/app_translation_constants.dart';

import 'app_camera_controller.dart';

class AppCameraPage extends StatelessWidget {

  const AppCameraPage({super.key});


  @override
  Widget build(BuildContext context) {

    return GetBuilder<AppCameraController>(
      id: AppPageIdConstants.camera,
      init: AppCameraController(),
      builder: (_) => Scaffold(
      appBar: AppBarChild(
        leadingWidget: IconButton(icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: AppTranslationConstants.newPost.tr, centerTitle: true,
      ),
      backgroundColor: AppColor.main50,
      body: SizedBox(
        child: Obx(()=> _.isLoading.value ? AppCircularProgressIndicator() : Stack(
        alignment: Alignment.center,
        children: [
          (!_.isDisposed) ? SizedBox(
            width: AppTheme.fullWidth(context),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50.0),
                bottomRight: Radius.circular(50.0),
              ),
              child: _.cameraPreviewWidget(),),
          ) : const CircularProgressIndicator(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: _.modeControlRowWidget(),
            )
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: GestureDetector(
                onTap: () {
                  if(_.controller != null && _.controller!.value.isInitialized && !_.controller!.value.isRecordingVideo) {
                    _.onTakePictureButtonPressed();
                  }
                },
                onLongPress: () {
                  if((_.userController.user.isVerified) && _.controller != null
                      && _.controller!.value.isInitialized && !_.controller!.value.isRecordingVideo) {
                    _.onVideoRecordButtonPressed();
                  }
                },
                onLongPressEnd: (details) {
                  if((_.userController.user.isVerified) && _.controller != null
                      && _.controller!.value.isInitialized && _.controller!.value.isRecordingVideo) {
                    _.onStopButtonPressed();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _.isRecording.value ? 90 : 80,
                  height: _.isRecording.value ? 90 : 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _.isRecording.value ? AppColor.red : AppColor.lightGrey,
                  ),
                  child: _.isRecording.value ? const Icon(Icons.stop, color: Colors.white, size: 45,) : null,
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
