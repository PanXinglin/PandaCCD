# panda_media

Local Android/iOS bridge for PandaCCD. This package does **not** implement filters,
beauty, face warping, or LUT processing. Those remain in Dart/GLSL in the host app.

Android uses bundled ML Kit for local face landmarks, MediaMetadataRetriever for
bounded video decoding, MediaCodec/EGL for H.264 encoding, and MediaMuxer for audio.
The encoder's GL program only uploads/swizzles pixels; it applies no image effect.
iOS uses Vision, AVFoundation, ImageIO and a matched Apple Live Photo identifier
plus timed still-image metadata. Photos inserts the prepared pair and returns the creation ID with add-only permission. Both SwiftPM and CocoaPods layouts are included.

No server, account, model download, analytics, or external face upload is involved.
Microphone permission belongs to the host and is requested only for optional Live
audio. Capture and camera lifecycle remain in the Flutter camera plugin.

API groups: detectPhoto/detectFrame/detectPixels; openReader/readPixels/closeReader;
openWriter/appendPixels/finishWriter/abortWriter; copyAudio; pairLive/savePhoto (iOS).
Native handles must be closed by the caller, including on failure. Flutter raw
images use explicit RGBA/BGRA flags and bounded dimensions; frames are sequential.

Validation and platform limitations: see ../../docs/LIVE_BEAUTY_0120.md.
