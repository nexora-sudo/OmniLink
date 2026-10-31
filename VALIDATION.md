# Validation — OmniLink 0.1.1 (build 3)

Verified on October 31, 2026.

- Flutter 3.47.9 / Dart 3.13.7, Windows x64.
- Static analysis: no issues found.
- Automated tests: 27 passed, including language selection, SQLite preference persistence, stored status display, diagnostic translation, and existing TLS/transfer tests.
- Android debug build: completed. APK signature verification passed (v2). Package org.omnilink.omnilink, versionName 0.1.1, versionCode 3, minSdk 24, targetSdk 36.
- Windows release x64 build: completed with EXE, DLLs, and assets.
- Windows GUI: opened version 0.1.1, observed English navigation and settings, selected Português (Brasil), and verified the interface changed immediately to Portuguese.
- Preference persistence across database reopen is covered by automated tests. Android language selection still needs physical-device UI testing.
- Physical-device pairing/transfers, Android gallery/SAF/camera, cross-device mDNS, startup integration, throughput, memory and FPS still require integrated validation.
- Native OS dialogs and third-party/system error details may follow the system language.

Logs are in validation/. The Android APK is development-signed for testing. Windows is a portable ZIP without an installer. The vendored desktop_drop Android registration patch remains in place; see packages/desktop_drop/OMNILINK_PATCH.md.
