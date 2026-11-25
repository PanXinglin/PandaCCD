# Panda CCD iOS port

Base: camera_avfoundation 0.10.3+1, official flutter/packages, BSD-3-Clause.
Original LICENSE and authors are retained. No native filter code is added.

`DefaultCamera.updateOrientation` now updates the photo connection even during
recording. The video/preview/analysis connection stays portrait, and is not
reconfigured during recording. This prevents the upstream recording guard from
ignoring the requested still-photo orientation and freezes the texture basis.

This MUST be used with our local camera `CameraPreview` iOS portrait-buffer
presentation, CameraSession portrait LiveSegment metadata, FaceTracker/Vision
normalization, and LiveProcessor mirror-before-rotate normalization. Do not
upgrade one component independently. Front buffers remain mirrored as upstream.

Native orientation expectations updated in CameraSetDeviceOrientationTests.
Those XCTest cases require Xcode; Dart geometry and Apple helper checks are
separate evidence, not a substitute for iPhone acceptance.
