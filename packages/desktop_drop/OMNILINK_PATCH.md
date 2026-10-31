Vendored from desktop_drop 0.6.1 (pub.dev). Original license: LICENSE.
Local patch: remove Android native plugin registration from pubspec.yaml.
OmniLink uses drag-and-drop only on Windows; Android uses the system file picker.
This avoids the upstream legacy Android/Kotlin build incompatibility with AGP 9.
Dart and Windows native implementation are unchanged. DropTarget is disabled on Android.
