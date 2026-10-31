# Known issues, limitations, and validation gaps

This page distinguishes implemented limitations from behavior that has not yet been validated. It is not a claim that every untested scenario is broken.

## Current limitations

| Area | What testers should expect |
| --- | --- |
| Android background operation | Keep the app in the foreground. There is no persistent background transfer service or guarantee of completion while the screen sleeps. |
| Language | English and Brazilian Portuguese are available in Settings → Language. Native OS dialogs and third-party diagnostic details may follow the system language. |
| Network | Both devices must be reachable on the same local network. This version supports private/link-local IPv4, not IPv6-only networks or CGNAT addresses in 100.64/10. |
| Discovery | Routers may block mDNS or isolate clients. Use manual connection details if discovery fails; isolation can also prevent manual connections. |
| File size | Maximum 4 GiB per file. |
| Android storage | Received files are private until manually exported. Uninstalling the app removes private files. A permanent SAF destination is not configured. |
| Packaging | Android uses a development-signed debug APK. Windows is an x64 ZIP without an installer. |
| Interrupted transfers | Resuming requires the source file to remain accessible. If Android's picker cache is cleared, select the original file again. |
| Recovery | A process crash between file finalization and database persistence may require manual recovery; see [PROTOCOL.md](PROTOCOL.md). |

## Still needs physical-device validation

- Pairing and transfers in both directions between Windows and Android.
- Android camera scanning, gallery/Downloads saving, SAF export, and sharing to other applications.
- mDNS across real routers, hardware-backed secure storage behavior, and Windows startup integration.
- Large-file throughput, memory use on midrange phones, and measured FPS.
- Wi-Fi interruption, cancellation, restarting either app, low storage, and resuming transfers.

## Verified so far

- Windows release and Android debug builds completed successfully.
- APK signature verification passed.
- 27 automated tests passed; static analysis reported no issues.
- The Windows app was opened and its Devices, Files, and Text screens were captured. The screenshots show an unpaired session, not a completed transfer.

See [VALIDATION.md](../VALIDATION.md) and [TESTING.md](TESTING.md) for the original build checks and manual test matrix.

## Troubleshooting

- **No devices found:** confirm both apps are open and on the same network. Avoid isolated guest Wi-Fi. Try a fresh invitation and manual connection.
- **Invitation rejected:** create a new one; invitations expire after five minutes, are single-use, and are revoked when their dialog closes.
- **File selection disabled:** pair a device and select it as the destination first.
- **Photo missing from the gallery:** wait for transfer completion, tap Save to gallery, check the OmniLink album, and allow time for the gallery to refresh. Try Downloads or Save as… if the gallery action reports an error. Support for displaying a format depends on installed apps.
- **Windows app fails to open after copying:** extract the entire ZIP; the executable requires its DLLs and `data` folder.

[Report a reproducible problem](https://github.com/nexora-sudo/OmniLink/issues/new?template=bug_report.md). Include OS versions, build number, steps, and the exact error. Do not publish invitation secrets, QR codes, credentials, or private files.
