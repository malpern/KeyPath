# ESP32 fixture could not join WPA3-SAE home Wi-Fi

## Symptom

The physical HID fixture booted normally and remained available as a USB HID
device, but cycled through its configured Wi-Fi profiles without obtaining an
address. Reflashing with the verified SSID and the password read directly from
the Mac's System keychain produced an identical firmware image, ruling out a
stale or mistyped credential.

## Cause

The home network uses WPA3-SAE. The fixture zero-initialized
`wifi_sta_config_t` and supplied the password and WPA2 minimum authentication
threshold, but did not select an SAE password-element derivation method.
Espressif's ESP-IDF station examples explicitly set `sae_pwe_h2e` for WPA3
connections.

## Fix

Personal Wi-Fi profiles now set `sae_pwe_h2e` to
`WPA3_SAE_PWE_BOTH`. The existing `WIFI_AUTH_WPA2_PSK` scan threshold remains
so WPA2-only fallback profiles are still eligible; the SAE setting is ignored
for those networks.

## Qualification

The production ESP32 firmware must build with the real encrypted configuration,
join the WPA3 home network after a cold boot, expose its authenticated status
endpoint, and complete a physical HID test before this incident is closed.

The first physical build with explicit SAE configuration still did not obtain
an address. Because Wi-Fi failure previously removed the only diagnostics
transport, the connecting screen now also reports the last disconnect reason in
plain language (with the numeric ESP-IDF reason as a fallback). The next
physical pass will distinguish an unavailable SSID, rejected authentication,
incompatible security, and handshake timeout before any further network change.
The same offline path identifies 802.1X login rejection, location authorization,
and unsupported channels for the Hacker Dojo enterprise profile.
The boot splash also shows the firmware version and source-derived build ID so
an operator can distinguish a stale image from the diagnostic build without a
working network connection.

The first diagnostic image reported `network not found` for every profile. The
home profile in that image had been changed from the previously working private
SSID to a different saved entry on the Mac. IPv6 had also been disabled on the
LAN, but that occurs after Wi-Fi association and cannot produce an SSID scan
failure. Version 0.3.1 restores the original configured SSID for physical
qualification while retaining WPA3 support and offline diagnostics.

Version 0.3.2 replaces the steady-state `CINEMATIC` badge with its short
firmware version. Wi-Fi failure phrases are capped at twelve characters and
the diagnostic label has a fixed one-line height, preventing long profile
names from wrapping.

## Physical result

Version 0.3.2, build `fc4565df2dc6`, joined the WPA3-SAE home network and
served an authenticated healthy status response at its expected address. The
response confirmed that USB HID was mounted, the display was advancing, the
OTA slot was valid, and no Wi-Fi disconnect had occurred since boot.

The initial flash did not leave the ROM USB Serial/JTAG bootloader when
esptool used its default RTS hard reset. An explicit esptool watchdog reset
started the application and changed the USB identity to
`KeyPath Physical HID Fixture`. The fixture flash command now performs that
recovery when necessary and refuses to report success until the runtime USB
identity appears. This keeps a successful flash write from being mistaken for
a successfully running fixture.
