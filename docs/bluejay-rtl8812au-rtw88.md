# Google Pixel 6a (bluejay): RTL8812AU / ALFA AWUS036ACH on LineageOS 23.2 + NetHunter

This document records the working build, integration, firmware, persistence, and validation path used to add external Realtek RTL8812AU Wi-Fi support to a Google Pixel 6a (`bluejay`) running LineageOS 23.2 / Android 16 with NetHunter.

It also records the paths that failed so other users do not have to repeat the same dead ends.

## Build environment

The kernel build and driver work documented here was performed on **Debian Linux**.

### Device

- Google Pixel 6a
- Codename: `bluejay`
- LineageOS 23.2 / Android 16
- Bootloader unlocked
- Magisk installed
- Magisk version observed: `30700` / 30.7
- NetHunter present
- Running kernel used for compatibility testing:
  - `6.1.145-android14-11-gedaaac4d5c85`

### External Wi-Fi adapter

- ALFA AWUS036ACH
- Chipset: Realtek RTL8812AU
- USB ID: `0bda:8812`
- Device string observed by Android:
  - `802.11n NIC`
- Final external interface name:
  - `wlan2`

### Kernel source

LineageOS Google GS 6.1 manifest:

~~~bash
repo init -u https://github.com/LineageOS/android_kernel_google_gs-6.1_manifest.git -b lineage-23.2
repo sync
~~~

Source root used:

~~~text
~/bluejay-kernel-src
~~~

Bluejay build entry point:

~~~text
private/devices/google/bluejay/build_bluejay.sh
~~~

The Bluejay build resolves to the Kleaf/Bazel device target:

~~~text
//private/devices/google/bluejay:gs101_bluejay_dist
~~~

## What did not work

### 1. Legacy aircrack-ng rtl8812au driver

The first attempt used:

~~~text
aircrack-ng/rtl8812au
version 5.6.4.2
~~~

A substantial number of source compatibility issues were patched for Linux 6.1 / Clang / Android GKI, including uninitialized variables, cfg80211 API changes, radiotap buffer sizing, and older driver logic.

The important failure happened at **modpost**, not normal C compilation.

The old driver requires kernel symbols including:

~~~text
filp_open
kernel_read
kernel_write
~~~

Those symbols are not exported to this Android GKI module environment. The result is that the legacy driver can be patched until it compiles, but it still cannot successfully link as an external GKI module without much more invasive kernel changes.

**Conclusion:** do not start with the deprecated rtl8812au driver for this Bluejay Android 6.1 GKI build.

### 2. Using the upstream rtw88 Makefile directly under Kleaf

The maintained driver selected after abandoning the legacy driver was:

~~~text
https://github.com/lwfinger/rtw88.git
~~~

The upstream Makefile was not directly compatible with the Android Kleaf external-module build.

Observed failures included:

~~~text
nproc: Unknown option 'ignore=1'
No rule to make target 'modules_install'
~~~

The solution was to preserve the upstream Makefile and replace the active Makefile with a minimal Kleaf-compatible wrapper.

### 3. Bazel visibility

The rtw88 target built independently, but the Bluejay device build initially could not depend on it because the Bazel target was not public.

Required:

~~~python
visibility = ["//visibility:public"],
~~~

Without that line, adding the module to Bluejay's `ext_modules` fails during analysis.

### 4. Missing firmware

The kernel modules can load successfully while the USB device still fails to create a usable PHY.

The exact failure was:

~~~text
rtw_8812au 1-1:1.0: Direct firmware load for rtw88/rtw8812a_fw.bin failed with error -2
rtw_8812au 1-1:1.0: failed to request firmware
rtw_8812au 1-1:1.0: failed to load firmware
rtw_8812au 1-1:1.0: failed to setup chip efuse info
rtw_8812au 1-1:1.0: failed to setup chip information
rtw_8812au: probe of 1-1:1.0 failed with error -22
~~~

The driver specifically requests:

~~~text
rtw88/rtw8812a_fw.bin
~~~

The firmware file from the rtw88 repository is:

~~~text
private/google-modules/rtw88/firmware/rtw8812a_fw.bin
~~~

Observed size:

~~~text
27030 bytes
~~~

The Android kernel firmware search path was:

~~~text
/vendor/firmware
~~~

### 5. Trying to change firmware_class path through sysfs

The kernel exposed:

~~~text
/sys/module/firmware_class/parameters/path
~~~

It reported:

~~~text
/vendor/firmware
~~~

However writing a temporary custom path failed:

~~~text
/system/bin/sh: can't create /sys/module/firmware_class/parameters/path: Permission denied
~~~

The sysfs filesystem itself was mounted read-write. The denial was still enforced by Android security policy / sysfs permissions.

Do not rely on changing this parameter at runtime.

### 6. Directly writing /vendor

`/vendor` was mounted read-only:

~~~text
/dev/block/dm-3 on /vendor type ext4 (ro,seclabel,noatime)
~~~

So directly creating:

~~~text
/vendor/firmware/rtw88/
~~~

is not a durable solution.

### 7. Android mount syntax

This form failed:

~~~bash
mount --bind /data/local/tmp/vendor_fw_overlay /vendor/firmware
~~~

with:

~~~text
mount: bad /etc/fstab: No such file or directory
~~~

The working Android/Toybox-compatible bind syntax was:

~~~bash
mount -o bind /data/local/tmp/vendor_fw_overlay /vendor/firmware
~~~

This was useful for the live proof-of-concept only. The final persistent solution uses Magisk.

### 8. ADB + su quoting matters

For multi-command root operations, this form proved reliable:

~~~bash
adb shell "su -c 'COMMANDS HERE'"
~~~

During troubleshooting, the other quoting form produced misleading permission/capability behavior.

A useful verification is:

~~~bash
adb shell "su -c 'grep CapEff /proc/\$\$/status'"
~~~

The working root shell showed:

~~~text
CapEff: 000001ffffffffff
~~~

This mattered for operations such as:

~~~text
iw dev wlan2 set type monitor
tcpdump -i wlan2
~~~

### 9. Wireless ADB IP can change after reboot

Before reboot the phone was reachable at:

~~~text
192.168.0.251:5555
~~~

After reboot, DHCP assigned:

~~~text
192.168.0.112
~~~

When wireless ADB stops working, reconnect the phone by USB and obtain the current WLAN address instead of assuming the old IP:

~~~bash
IP=$(adb shell "ip -4 -o addr show wlan0 | awk '{print \$4}' | cut -d/ -f1" | tr -d '\r')
echo "$IP"
adb tcpip 5555
adb connect "$IP:5555"
~~~

## Working driver: lwfinger/rtw88

Clone into the Google module tree:

~~~bash
cd ~/bluejay-kernel-src/private/google-modules
git clone https://github.com/lwfinger/rtw88.git
~~~

The RTL8812AU USB ID is supported by the maintained rtw88 USB driver.

The module chain used is:

~~~text
rtw_core
rtw_usb
rtw_88xxa
rtw_8812a
rtw_8812au
~~~

Dependency relationships observed with `modinfo`:

~~~text
rtw_core      -> mac80211,cfg80211
rtw_usb       -> rtw_core,mac80211
rtw_88xxa     -> rtw_core
rtw_8812a     -> rtw_88xxa,rtw_core
rtw_8812au    -> rtw_8812a,rtw_usb
~~~

## Kleaf Kbuild

Create:

~~~text
private/google-modules/rtw88/Kbuild
~~~

with:

~~~make
ccflags-y += -O2 -std=gnu11 -Wno-declaration-after-statement
ccflags-y += -DCONFIG_RTW88_LEDS=1
ccflags-y += -DCONFIG_RTW88_DEBUG=1
ccflags-y += -DCONFIG_RTW88_DEBUGFS=1
ccflags-y += -D__CHECK_ENDIAN__

obj-m += rtw_core.o
rtw_core-objs += main.o led.o mac80211.o util.o debug.o tx.o rx.o mac.o phy.o coex.o efuse.o fw.o ps.o sec.o bf.o regd.o sar.o

ifeq ($(CONFIG_PM), y)
rtw_core-objs += wow.o
endif

obj-m += rtw_usb.o
rtw_usb-objs := usb.o

obj-m += rtw_88xxa.o
rtw_88xxa-objs := rtw88xxa.o

obj-m += rtw_8812a.o
rtw_8812a-objs := rtw8812a.o rtw8812a_table.o

obj-m += rtw_8812au.o
rtw_8812au-objs := rtw8812au.o
~~~

## Kleaf-compatible Makefile

Preserve the original:

~~~bash
mv private/google-modules/rtw88/Makefile private/google-modules/rtw88/Makefile.upstream
~~~

Create a replacement `private/google-modules/rtw88/Makefile`:

~~~make
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
M ?= $(CURDIR)

.PHONY: all modules modules_install clean

all: modules

modules:
	$(MAKE) -C $(KERNEL_SRC) M=$(M) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(M) modules_install

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(M) clean
~~~

## Bazel target

Create:

~~~text
private/google-modules/rtw88/BUILD.bazel
~~~

with:

~~~python
load("//build/kernel/kleaf:kernel.bzl", "kernel_module")

kernel_module(
    name = "rtw88",
    visibility = ["//visibility:public"],
    srcs = glob([
        "**/*.c",
        "**/*.h",
    ]) + [
        "Kbuild",
    ],
    outs = [
        "rtw_core.ko",
        "rtw_usb.ko",
        "rtw_88xxa.ko",
        "rtw_8812a.ko",
        "rtw_8812au.ko",
    ],
    kernel_build = "//private/devices/google/common:kernel",
)
~~~

## Build the external module first

From:

~~~text
~/bluejay-kernel-src
~~~

run:

~~~bash
tools/bazel build --config=bluejay //private/google-modules/rtw88:rtw88
~~~

Expected outputs:

~~~text
bazel-bin/private/google-modules/rtw88/rtw88/rtw_core.ko
bazel-bin/private/google-modules/rtw88/rtw88/rtw_usb.ko
bazel-bin/private/google-modules/rtw88/rtw88/rtw_88xxa.ko
bazel-bin/private/google-modules/rtw88/rtw88/rtw_8812a.ko
bazel-bin/private/google-modules/rtw88/rtw88/rtw_8812au.ko
~~~

The standalone module initially reported a `maybe-dirty` vermagic during development. The final full Bluejay build produced the exact device kernel vermagic:

~~~text
6.1.145-android14-11-gedaaac4d5c85 SMP preempt mod_unload modversions aarch64
~~~

The final module must match the running kernel sufficiently for Android to accept it.

## Integrate rtw88 into the Bluejay device build

Edit:

~~~text
private/devices/google/bluejay/BUILD.bazel
~~~

and add the rtw88 target to the Bluejay `ext_modules` list:

~~~python
"//private/google-modules/rtw88:rtw88",
~~~

The placement used was immediately after the Samsung cpif.dit module entry, but the important part is that it is inside the device's external module list.

## Full Bluejay build

Run:

~~~bash
private/devices/google/bluejay/build_bluejay.sh
~~~

Successful build output included:

~~~text
Creating vendor_dlkm image
Trimming unused modules
Target //private/devices/google/bluejay:bluejay/dist up-to-date
Build completed successfully
Copying to /home/m4ck/bluejay-kernel-src/out/bluejay/dist
~~~

Generated files included:

~~~text
out/bluejay/dist/rtw_core.ko
out/bluejay/dist/rtw_usb.ko
out/bluejay/dist/rtw_88xxa.ko
out/bluejay/dist/rtw_8812a.ko
out/bluejay/dist/rtw_8812au.ko
out/bluejay/dist/vendor_dlkm.img
out/bluejay/dist/vendor_dlkm.modules.load
~~~

The generated `vendor_dlkm.modules.load` contained the modules in the correct order:

~~~text
extra/private/google-modules/rtw88/rtw_core.ko
extra/private/google-modules/rtw88/rtw_usb.ko
extra/private/google-modules/rtw88/rtw_88xxa.ko
extra/private/google-modules/rtw88/rtw_8812a.ko
extra/private/google-modules/rtw88/rtw_8812au.ko
~~~

## Live module test before persistence

Push the built modules and firmware to a temporary directory:

~~~bash
adb shell 'mkdir -p /data/local/tmp/rtw88/rtw88'
adb push out/bluejay/dist/rtw_*.ko /data/local/tmp/rtw88/
adb push private/google-modules/rtw88/firmware/rtw8812a_fw.bin /data/local/tmp/rtw88/rtw88/
~~~

Load in dependency order using a correctly quoted root shell:

~~~bash
adb shell "su -c 'insmod /data/local/tmp/rtw88/rtw_core.ko'"
adb shell "su -c 'insmod /data/local/tmp/rtw88/rtw_usb.ko'"
adb shell "su -c 'insmod /data/local/tmp/rtw88/rtw_88xxa.ko'"
adb shell "su -c 'insmod /data/local/tmp/rtw88/rtw_8812a.ko'"
adb shell "su -c 'insmod /data/local/tmp/rtw88/rtw_8812au.ko'"
~~~

Verify:

~~~bash
adb shell "su -c 'lsmod | grep rtw'"
~~~

All five modules loaded successfully on the tested kernel.

## Live firmware proof

Because `/vendor` is read-only, a temporary bind overlay was used to prove the firmware was correct before making it persistent.

Create the overlay:

~~~bash
adb shell su -c 'rm -rf /data/local/tmp/vendor_fw_overlay && mkdir -p /data/local/tmp/vendor_fw_overlay/rtw88 && cp -a /vendor/firmware/. /data/local/tmp/vendor_fw_overlay/ && cp /data/local/tmp/rtw88/rtw88/rtw8812a_fw.bin /data/local/tmp/vendor_fw_overlay/rtw88/'
~~~

Bind it:

~~~bash
adb shell su -c 'mount -o bind /data/local/tmp/vendor_fw_overlay /vendor/firmware'
~~~

Verify:

~~~bash
adb shell su -c 'ls -l /vendor/firmware/rtw88/rtw8812a_fw.bin'
~~~

After unplugging and reconnecting the ALFA adapter, the firmware loaded:

~~~text
rtw_8812au 1-1:1.0: Firmware version 52.14.0, H2C version 0
~~~

The adapter then created:

~~~text
phy#3
Interface wlan2
~~~

The device may re-enumerate from USB bus 1 to bus 2 during initialization. Messages such as:

~~~text
write register 0x5 failed with -71
~~~

were observed immediately before re-enumeration, but the adapter subsequently initialized correctly on this setup. Do not treat that line by itself as the final failure; inspect the following USB and rtw88 messages.

## Confirm RTL8812AU USB enumeration

With the ALFA connected through USB OTG:

~~~bash
lsusb
~~~

Observed:

~~~text
Bus 001 Device 002: ID 0bda:8812
~~~

If `0bda:8812` is not visible, fix USB host/OTG detection before troubleshooting the driver.

## Confirm monitor-mode capability

Once the external PHY exists:

~~~bash
iw phy phy3 info | grep -A 20 "Supported interface modes"
~~~

The tested driver reported:

~~~text
IBSS
managed
AP
AP/VLAN
monitor
P2P-client
P2P-GO
~~~

The PHY number is not stable across reconnects/reboots. Later testing showed `phy#6`. Use `iw dev` to identify the current PHY/interface rather than hard-coding the PHY number.

The external interface remained:

~~~text
wlan2
~~~

in the tested configuration.

## Switch wlan2 to monitor mode

Use a root shell with full capabilities:

~~~bash
adb shell "su -c 'ip link set wlan2 down && iw dev wlan2 set type monitor && ip link set wlan2 up && iw dev wlan2 info'"
~~~

Successful output includes:

~~~text
type monitor
link/ieee802.11/radiotap
~~~

Example confirmed state:

~~~text
Interface wlan2
    type monitor
    channel 1 (2412 MHz)
    txpower 20.00 dBm
~~~

## Set a channel

Example for channel 36 / 5180 MHz:

~~~bash
adb shell "su -c 'iw dev wlan2 set channel 36 && iw dev wlan2 info'"
~~~

Confirmed:

~~~text
channel 36 (5180 MHz), width: 20 MHz (no HT)
~~~

## Verify real 802.11 capture

With `wlan2` in monitor mode:

~~~bash
adb shell "su -c 'tcpdump -i wlan2 -c 20 -e -s 256'"
~~~

The working setup captured radiotap/802.11 traffic including:

- Beacons
- RTS
- CTS
- ACK
- Block ACK
- encrypted data frames

A test against the owner's own lab WLAN captured the SSID beacon and channel information and ended with:

~~~text
20 packets captured
58 packets received by filter
0 packets dropped by kernel
~~~

This proves monitor-mode receive/capture functionality, not just that the interface accepted the word `monitor`.

## Persistent Magisk deployment

Although the full Bluejay kernel build generated a `vendor_dlkm.img` containing the modules, the tested phone persistence path documented here used **Magisk**, avoiding a vendor_dlkm flash during development.

Create a module staging directory on Debian:

~~~bash
rm -rf /tmp/rtw88-magisk
mkdir -p /tmp/rtw88-magisk/system/vendor/firmware/rtw88

cp out/bluejay/dist/{rtw_core,rtw_usb,rtw_88xxa,rtw_8812a,rtw_8812au}.ko /tmp/rtw88-magisk/
cp private/google-modules/rtw88/firmware/rtw8812a_fw.bin /tmp/rtw88-magisk/system/vendor/firmware/rtw88/
~~~

Create `module.prop`:

~~~text
id=rtw88bluejay
name=Bluejay RTW88 WiFi
version=1.0
versionCode=1
author=m4ckDev
description=RTL8812AU RTW88 driver and firmware for Bluejay
~~~

Create `service.sh`:

~~~sh
#!/system/bin/sh
MODDIR="$(dirname "$0")"
sleep 3

insmod "$MODDIR/rtw_core.ko" 2>/dev/null
insmod "$MODDIR/rtw_usb.ko" 2>/dev/null
insmod "$MODDIR/rtw_88xxa.ko" 2>/dev/null
insmod "$MODDIR/rtw_8812a.ko" 2>/dev/null
insmod "$MODDIR/rtw_8812au.ko" 2>/dev/null
~~~

Make it executable:

~~~bash
chmod 755 /tmp/rtw88-magisk/service.sh
~~~

Push the module to the phone:

~~~bash
adb push /tmp/rtw88-magisk/. /data/local/tmp/rtw88bluejay/
~~~

Install it using the reliably quoted root shell:

~~~bash
adb shell "su -c 'mkdir -p /data/adb/modules/rtw88bluejay && cp -a /data/local/tmp/rtw88bluejay/. /data/adb/modules/rtw88bluejay/ && chmod 755 /data/adb/modules/rtw88bluejay/service.sh'"
~~~

Reboot:

~~~bash
adb reboot
~~~

## Persistence verification after reboot

After reboot, the tested phone showed all five modules loaded automatically:

~~~text
rtw_8812au
rtw_8812a
rtw_88xxa
rtw_usb
rtw_core
~~~

The firmware also appeared persistently through Magisk:

~~~text
/vendor/firmware/rtw88/rtw8812a_fw.bin
~~~

After reconnecting the ALFA, kernel logs showed:

~~~text
rtw_8812au ... Firmware version 52.14.0, H2C version 0
~~~

and `iw dev` again showed:

~~~text
Interface wlan2
type managed
~~~

The interface was then switched back into monitor mode and packet capture was successfully repeated after reboot.

This is the final proof that the driver + firmware configuration survived reboot.

## Final working state

The completed test established all of the following:

- RTL8812AU modules compile against the LineageOS Bluejay Android 6.1 kernel.
- The modules are accepted by the running kernel.
- The exact RTL8812AU firmware loads.
- ALFA AWUS036ACH USB ID `0bda:8812` binds to `rtw_8812au`.
- A separate external wireless PHY is created.
- The external interface appears as `wlan2`.
- `wlan2` supports monitor mode.
- Channel switching works.
- Radiotap 802.11 capture works.
- Monitor-mode packet capture was verified with actual frames.
- The configuration survives reboot using Magisk.

## Recommended troubleshooting order

If another Bluejay user follows this work and it fails, troubleshoot in this order:

1. Confirm exact running kernel with `uname -a`.
2. Confirm the built module vermagic with `modinfo`.
3. Confirm `0bda:8812` appears in `lsusb`.
4. Confirm all five rtw88 modules are loaded with `lsmod | grep rtw`.
5. Inspect `dmesg` for `rtw_8812au`.
6. If firmware error `-2` appears, verify `/vendor/firmware/rtw88/rtw8812a_fw.bin`.
7. Run `iw dev` and confirm a separate external PHY/interface.
8. Verify full root capabilities before blaming `iw` or `tcpdump`.
9. Switch the external interface down before changing its type.
10. Test a known channel with passive packet capture.
11. Only after live testing succeeds, make the deployment persistent.

## Important distinction: kernel integration vs tested deployment

The Bluejay source tree was successfully modified so the modules are incorporated into the full device build and generated `vendor_dlkm.img`.

However, the **tested deployment on the phone described in this document uses the Magisk module path** for persistence.

That distinction matters for anyone reproducing this work:

- **Build integration:** confirmed.
- **Generated vendor_dlkm with modules:** confirmed.
- **Flashing the newly generated vendor_dlkm image as part of this specific test:** not performed.
- **Magisk module persistence:** confirmed after reboot.
- **Monitor mode and packet capture after reboot:** confirmed.

## Responsible use

Monitor mode exposes raw 802.11 traffic. Use it only on devices and networks you own or have explicit authorization to assess.
