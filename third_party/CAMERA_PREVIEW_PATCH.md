# Official camera preview continuity patch

Source: Flutter camera_android_camerax 0.7.6 (BSD-3-Clause; original LICENSE retained).
Dependency override: `third_party/camera_android_camerax`.

The original 0.10.1 preview-continuity patch changes these two upstream Dart files (additional 0.10.3 changes are described below):

- `lib/src/surface_texture_rotated_preview.dart`
- `lib/src/image_reader_rotated_preview.dart`

Both originally returned `SizedBox.shrink()` whenever their asynchronous display
rotation query was waiting. Every physical orientation event replaces that future,
unmounting the texture for one or more frames even if the camera controller stays
alive. This explains why controller-identity tests alone cannot catch the blink.

The patch seeds FutureBuilder with the known initial display rotation and uses
its retained last data while a new query is pending. The texture stays mounted;
rotation, mirroring, sensor transforms and capture logic remain upstream logic.
There are no Kotlin/Java changes, native filters, or added platform capability APIs.
The iOS endorsed implementation remains unchanged.

Regression: `test/preview_continuity_test.dart` holds each display query unresolved
for six frames and checks the live texture never disappears or changes element.
Both SurfaceTexture and ImageReader paths are exercised.

Upstream context:
https://github.com/flutter/packages/tree/main/packages/camera/camera_android_camerax
https://github.com/flutter/flutter/issues/190907

The known naturally-landscape foldable issue is separate from this continuity patch;
this patch does not claim to fix every sensor/display-rotation combination.
When updating the camera plugin, check whether upstream retains the preview while
queries wait, rerun these tests, and remove the local override if superseded.

## Independent capture/presentation orientation

A second small local override contains official `camera` 0.12.1, BSD-3-Clause.
Only `lib/src/camera_preview.dart` differs: the optional `previewOrientation`
argument selects presentation independently of `lockedCaptureOrientation`.
Default behavior is unchanged for callers that omit the argument.

Compact capture uses the official `lockCaptureOrientation` immediately before
`takePicture` and unlocks in `finally`. This is required because the Android
implementation normally uses display rotation when the window stays portrait.
The camera page supplies its fixed window orientation to the preview, preventing
that temporary photo orientation from turning the preview. Expanded windows retain
the OS/plugin capture orientation instead of guessing from natural sensor axes.

No files in either package's Android/iOS/native directories were changed. These
are presentation changes in Dart; the application's LUT/GLSL filters stay shared.
The iOS build/runtime still needs device validation, especially the AVFoundation
preview during a temporary capture lock; Android simulator success is not iOS proof.

## 0.10.3: canonical window orientation refresh

`camera_android_camerax/lib/src/android_camera_camerax.dart` now observes Flutter
window metrics while a camera exists. After the changed window's frame, it reads
canonical UI orientation through the plugin's existing native API and publishes
it through the original orientation stream. It unregisters and invalidates pending
queries on disposal. Previously this refresh depended entirely on the next native
sensor event, which could precede the configuration update or stop at a fixed angle.
There is no new native camera code or additional platform API.

The separately approved Android application shell change in MainActivity requests
ROTATION_ANIMATION_SEAMLESS. It is window presentation configuration, not a filter
or camera pipeline implementation. User approval: conversation, 2026-10-30.
