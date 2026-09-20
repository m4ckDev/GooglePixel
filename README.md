# GooglePixel

Improvements, security solutions, and reproducible technical notes for Google Pixel devices.

## Pixel 6a / bluejay

### RTL8812AU external Wi-Fi support

A full Debian Linux build and troubleshooting record is available for adding ALFA AWUS036ACH / RTL8812AU support to a Pixel 6a running LineageOS 23.2 / Android 16 with NetHunter.

The documented result includes:

- maintained `lwfinger/rtw88` driver integration
- Android Kleaf/Bazel external-module build
- Bluejay `vendor_dlkm` integration
- exact firmware requirement and Android firmware-path troubleshooting
- known failures with the legacy `aircrack-ng/rtl8812au` driver
- Magisk-based persistent deployment
- monitor-mode verification
- channel switching
- confirmed radiotap/802.11 packet capture after reboot

See:

- [Bluejay RTL8812AU / RTW88 build and troubleshooting guide](docs/bluejay-rtl8812au-rtw88.md)
- [Magisk module staging helper](scripts/build-rtw88-magisk-module.sh)

## Scope

This repository is intended for device improvement, security research, and authorized lab use.
