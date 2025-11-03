# neom_camera
neom_camera is a specialized module within the Open Neom ecosystem, dedicated to providing
robust camera functionalities for capturing photos and videos. It offers a direct interface
for users to access their device's camera, control various settings (like flash mode),
and capture media for integration into the application's content creation workflows.

This module is designed to provide a seamless and efficient media capture experience,
abstracting the complexities of camera hardware interaction. It adheres strictly to
Open Neom's Clean Architecture principles, ensuring its logic is robust, testable,
and decoupled from direct UI presentation. 

It seamlessly integrates with neom_core for core services and neom_commons for shared
UI components, providing a cohesive camera experience. Its focus on enabling direct
media capture aligns with the Tecnozenism philosophy of empowering conscious digital expression.

🌟 Features & Responsibilities
neom_camera provides a comprehensive set of functionalities for camera control and media capture:
•	Photo Capture: Allows users to take high-resolution photos using the device's camera.
•	Video Recording: Supports recording videos, with features like automatic stopping based on
    user role (e.g., subscriber vs. admin) to manage video duration limits.
•	Camera Control: Provides controls for:
    o	Switching between front and back cameras.
    o	Adjusting flash modes (off, auto, on, torch).
    o	Toggling audio recording for videos.
    o	Setting exposure and focus points via tap-to-focus.
    o	Controlling zoom levels.
•	Live Camera Preview: Displays a real-time preview from the camera, allowing users to frame their shots.
•	Permission Handling: Manages camera and audio access permissions, providing user feedback if access is denied.
•	Media Output: Returns captured photos (XFile) and videos (XFile) as File objects, ready for further processing
    by other modules (e.g., neom_media_upload).
•	User Role Integration: Adapts video recording duration limits based on the user's verification level or role.

🛠 Technical Highlights / Why it Matters (for developers)
For developers, neom_camera serves as an excellent case study for:
•	External Camera Library Integration: Demonstrates effective integration of the camera Flutter package
    for direct hardware camera access and control.
•	GetX for State Management: Utilizes GetX's AppCameraController for managing reactive state related
    to camera operations (e.g., isLoading, isRecording, enableAudio) and orchestrating camera
    lifecycle events (initialization, disposal).
•	Service-Oriented Architecture: Implements the AppCameraService interface (defined in neom_core),
    showcasing how complex hardware interactions are exposed through an abstraction, allowing other
    modules (e.g., neom_media_upload) to trigger camera actions without direct coupling.
•	Platform-Specific Camera Handling: Manages various CameraException codes and adapts behavior
    for different platforms (e.g., iOS-specific permission messages).
•	Gesture-Based Camera Controls: Implements GestureDetector for tap-to-focus and pinch-to-zoom
    functionalities on the camera preview.
•	Timer-Based Video Recording: Shows how to implement timed video recording to enforce duration limits.
•	UI for Camera Controls: Provides examples of building custom UI elements for camera mode controls (flash, audio).

How it Supports the Open Neom Initiative
neom_camera is vital to the Open Neom ecosystem and the broader Tecnozenismo vision by:
•	Enabling Rich Content Creation: Provides the fundamental capability for users to capture original
    photos and videos, enriching user-generated content within the platform.
•	Facilitating Biofeedback & Research: The ability to capture raw video (e.g., for facial expression
    analysis, movement tracking) or photos could be leveraged for specific research protocols 
    in neuroscientific and biofeedback applications.
•	Enhancing User Engagement: Offers an intuitive and efficient way for users to create and share visual content,
    contributing to a more dynamic and interactive platform.
•	Supporting Digital Expression: Empowers users to document and share their experiences, aligning with 
    the Tecnozenism principle of conscious digital expression.
•	Showcasing Modularity: As a specialized, self-contained module, it exemplifies Open Neom's "Plug-and-Play"
    architecture, demonstrating how complex hardware interactions can be encapsulated and integrated seamlessly.

🚀 Usage
This module provides the AppCameraPage for the camera UI and the AppCameraController which implements AppCameraService.
Other modules (e.g., neom_media_upload when a user wants to take a new photo/video) can call methods from AppCameraService
to initiate camera operations and receive the captured media file.

📦 Dependencies
neom_camera relies on neom_core for core services, models, and routing constants, and on neom_commons for reusable UI
components, themes, and utility functions. It directly depends on the camera Flutter package for its core functionality.

🤝 Contributing
We welcome contributions to the neom_camera module! If you're passionate about camera functionalities,
performance optimization for video capture, or integrating advanced camera features, your contributions
can significantly enhance Open Neom's media capabilities.

To understand the broader architectural context of Open Neom and how neom_camera fits into the overall 
vision of Tecnozenism, please refer to the main project's MANIFEST.md.

For guidance on how to contribute to Open Neom and to understand the various levels of learning and engagement
possible within the project, consult our comprehensive guide: Learning Flutter Through Open Neom: A Comprehensive Path.

📄 License
This project is licensed under the Apache License, Version 2.0, January 2004. See the LICENSE file for details.
