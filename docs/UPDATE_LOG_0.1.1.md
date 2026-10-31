# OmniLink v0.1.1 — Update log

## Added

- English interface alongside Brazilian Portuguese.
- Language selector in **Settings → Language**: **English** or **Português (Brasil)**.
- Immediate language switching without restarting the application.
- Persistent language preference, restored the next time OmniLink opens.

## Updated

- Navigation, device discovery, pairing invitations, QR scanning, file transfers, text sharing, settings, and save actions now follow the selected language.
- Connection and transfer states have localized display labels while preserving existing stored values and protocol compatibility.
- Application-owned pairing confirmations, validation messages, and storage errors have English translations.
- New installations and installations without a saved language preference start in English. Portuguese remains available in settings.
- Application version updated to **0.1.1**, build **3**.

## Validation

- 27 automated tests passed, including language switching, SQLite persistence, status labels, and diagnostic translations.
- Native OS dialogs and third-party/system error details may follow the operating system's language.
- Physical-device transfer and Android gallery validation remain pending.

## Installation

- **Android:** install `OmniLink-0.1.1-android.apk` over the previous development-signed build.
- **Windows:** extract the entire `OmniLink-0.1.1-windows-x64.zip` and run `omnilink.exe`. Keep all DLLs and the `data` folder together.
- To switch back to Portuguese, open **Settings → Language → Português (Brasil)**.
