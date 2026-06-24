# Head Unit ADB Script

ADB-based Android APK installer for aftermarket and OEM head units. Connects to your device over Wi-Fi, lets you pick apps from a curated catalog, and installs them — no PC-side Android setup required.

---

## Usage

### macOS / Linux
```bash
curl -fsSL https://raw.githubusercontent.com/iMrLopez/headunit-adb-scripts/refs/heads/main/run.sh | bash
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/iMrLopez/headunit-adb-scripts/refs/heads/main/run.ps1 | iex
```

> Your device must have **wireless ADB enabled** and be on the same network as your computer.

---

## App Catalog

Apps are managed in [`app-catalog.json`](./app-catalog.json). Each entry declares a name, a download type, and a source. Supported types:

| Type | Description |
|---|---|
| `gitrelease` | Fetches the latest `.apk` from a GitHub release |
| `gitcollection` | Lists all `.apk` assets from a GitHub release for you to choose |
| `directdownload` | Downloads directly from a URL |

---

## Tested Vehicles

| Vehicle | Status |
|---|---|
| Riddara RD6 Max 4×4 | ✅ Tested |

If you've tested this on another vehicle, feel free to open an issue or PR to add it to the list.

---

## Disclaimer

**Use this at your own risk.**

Installing third-party APKs on your head unit may void your warranty, cause instability, or result in data loss. Neither the author nor any contributors are responsible for any damage caused to your vehicle, head unit, or data as a result of using these scripts.

**This script is free and will always be free.** If someone is charging you money to run it, you are being scammed. Do not pay anyone for access to this repository or its contents.

---

## Support the Project

If this script saved you time or money, consider buying me a coffee ☕

👉 **[paypal.me/MyndsIT](https://paypal.me/MyndsIT)**

Donations are never required but always appreciated.

---

*by [iMrLopez](https://github.com/iMrLopez)*
