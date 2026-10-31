# Quick start for testers

## 1. Download

Open the [latest release](https://github.com/nexora-sudo/OmniLink/releases/latest).

- **Windows x64:** download the Windows ZIP, extract everything, and open `omnilink.exe`. Keep the DLLs and `data` folder next to the executable. There is no installer yet.
- **Android 7+:** download and open the APK. Allow installation from your chosen source if Android requests it. This is a development-signed debug build for testing. Install it over your previous OmniLink build when possible.

No account is required. Internet access is only needed to download the packages; sharing uses your local network.

## 2. Connect the devices

Connect both devices to the same Wi-Fi/router. The PC may use Ethernet on the same network. Keep OmniLink open on both devices.

On Windows, if a firewall prompt appears, allow the application on your trusted private network. The default TCP port is 45832 and mDNS uses UDP 5353. Guest Wi-Fi or client isolation may prevent devices from reaching each other.

## 3. Pair

The app defaults to English when no preference is saved. Choose English or Português (Brasil) in Settings → Language. The steps below include Portuguese labels for reference.

1. On Windows, select **Criar convite** (Create invitation).
2. On Android, select **Ler QR Code** (Scan QR code) and scan the invitation. Camera access is required for scanning.
3. Confirm the device name/address on the device that created the invitation.
4. If discovery or scanning fails, use **Conectar / IP manual** (Connect / Manual IP) and the invitation's manual connection details. Select the network address that belongs to the same network as the other device.

Invitations are single-use and expire after five minutes. Closing the invitation dialog revokes it. Create a fresh invitation if necessary. Do not post QR codes, secret codes, or full invitations in public bug reports.

## 4. Send your first file

1. Open **Arquivos** (Files).
2. Select the paired destination device.
3. Choose a small test file with **Selecionar arquivos** (Select files), or drag a file into the Windows app.
4. Accept the incoming transfer on the receiving device.
5. Wait for completion and integrity verification. Repeat in the other direction.

Files are limited to 4 GiB each. Keep the Android app in the foreground during testing.

## 5. Save a received file

- **Android photos/videos:** choose **Salvar na galeria** (Save to gallery). Look for the OmniLink album. Your gallery may need a moment to refresh.
- **Any file:** choose **Salvar em Downloads** (Save to Downloads). On Windows, the default receive location is already `Downloads/OmniLink`.
- **Android, another location:** choose **Salvar em…** (Save as…) and select a destination in the system picker.

Saving is manual and preserves the private received copy. Export files you want to keep before uninstalling the Android app. Android 7–9 may request storage permission when saving to a public folder.

## 6. Help test

Try pairing, sending a photo in both directions, saving it, and sharing a short text. Only then try larger files or interrupt Wi-Fi to test resuming. These physical-device scenarios still need validation.

If something fails, check [known issues and limitations](KNOWN_ISSUES.md) and [open a bug report](https://github.com/nexora-sudo/OmniLink/issues/new?template=bug_report.md). Include your OS, OmniLink build, steps, expected result, and actual result. Remove personal data, local addresses, secrets, and private file contents from screenshots or logs.
