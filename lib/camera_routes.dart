import 'package:get/get.dart';

import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'ui/app_camera_page.dart';

class CameraRoutes {

  static final List<GetPage<dynamic>> routes = [
    GetPage(
      name: AppRouteConstants.camera,
      page: () => const AppCameraPage(),
      transition: Transition.downToUp,
    ),
  ];

}
