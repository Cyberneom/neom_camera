### 1.0.0 - Initial Release & Decoupling from neom_posts
This marks the initial official release (v1.0.0) of neom_camera as a standalone, independent module within the Open Neom ecosystem. Previously, camera functionalities (such as taking photos for post creation) were often embedded directly within content creation modules like neom_posts. This decoupling is a crucial step in formalizing the media capture layer, enhancing modularity, and strengthening Open Neom's adherence to Clean Architecture principles.

Key Highlights of this Release:

Module Decoupling & Self-Containment:

neom_camera now exclusively encapsulates all camera-related logic, including photo and video capture, and camera controls.

This ensures that neom_camera is a highly focused and reusable component for any media capture requirement across the application.

Centralized Camera Functionality:

Provides a dedicated and robust interface for interacting with the device's camera, including:

Taking photos.

Recording videos (with duration limits based on user role).

Controlling flash modes, audio, zoom, and focus/exposure points.

Utilizes the camera Flutter package as its core external dependency, ensuring a high-quality, platform-optimized capture experience.

Enhanced Maintainability & Future Scalability:

As a dedicated and self-contained module, neom_camera is now significantly easier to maintain, test, and extend for future camera features (e.g., advanced filters, AR capabilities).

Any module requiring camera access (like neom_media_upload for processing captured media) can simply depend on neom_camera and its AppCameraService.

This aligns perfectly with the overall architectural vision of Open Neom, fostering a more collaborative and efficient development environment for media capture.

Leverages Core Open Neom Modules:

Built upon neom_core for foundational services (like UserService for user role-based limits) and neom_commons for reusable UI components and utilities, ensuring consistency and seamless integration within the ecosystem.
