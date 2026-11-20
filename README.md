# Brokenithm (v1e3d)

This repository holds:

| Path | What |
|---|---|
| `/` (root) | **Brokenithm-SwiftUI** iPad/iPhone app with the cabinet-style 16x2 slider. Every push builds an unsigned IPA (Actions -> "Build IPA" -> artifact). |
| `pc-receiver/` | **Brokenithm-LAN** Windows receiver (Wi-Fi) with camera AIR. See `pc-receiver/README.md`. |
| `legacy-objc/` | The original Objective-C Brokenithm-iOS (USB) this fork started from, kept for reference. |

# Brokenithm-SwiftUI

Turn your iPhone or iPad into a CHUNITHM controller.

Brokenithm-SwiftUI is a native, low-latency touch controller for SEGA's CHUNITHM. Put your device in front of your screen, connect to the Brokenithm server on your PC, and play with a full 32-lane slider and air input, no arcade hardware required.

Based on the original Brokenithm concept by [esterTion](https://github.com/esterTion/Brokenithm-iOS), rebuilt from the ground up in SwiftUI.

## Features

- **Full 32-lane slider** with multi-touch, so slides, holds and flicks all register the way you expect.
- **Air input** you can toggle on and off, with three air-zone heights (Small, Normal, Large) to suit your device and play style.
- **Live LED feedback** from the game lights up the slider on your screen just like the real cabinet.
- **Tap Card and Insert Coin** buttons right in the menu, so you never have to reach for the keyboard.
- **Automatic discovery**: the app advertises itself on your local network, so the PC finds it without typing IP addresses.
- **Connection status at a glance**: the top bar glows green when connected and red when not, with a one-tap restart.
- **iPhone and iPad** layouts, built for iOS 18 and later.

## Installation

### Option 1: TestFlight (recommended)

1. Install [TestFlight](https://apps.apple.com/app/testflight/id899247664) from the App Store.
2. Open the invite link on your device: **https://testflight.apple.com/join/U6kwvETm**
3. Tap **Install**. Updates arrive automatically through TestFlight, with a fresh build published every month.

### Option 2: Sideload the IPA

Every [release](https://github.com/OWCramer/Brokenithm-SwiftUI/releases) includes an unsigned `.ipa` you can install yourself.

1. Download `Brokenithm-SwiftUI-<version>-unsigned.ipa` from the latest release.
2. Install it with your preferred sideloading tool, such as [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io), signing in with your own Apple ID.
3. If iOS refuses to open the app, go to **Settings → General → VPN & Device Management** and trust your developer profile.

Free Apple IDs need to re-sign sideloaded apps every 7 days. TestFlight has no such limit.

## Slider: 16 keys x 2 rows (this branch)

The cabinet's slider has 32 sensors: 16 keys, each split into a top and a bottom half
(sensor 1 = top-right, 2 = bottom-right, ... 31 = top-left, 32 = bottom-left).
This build sends the same layout:

- **Split Keys Top/Bottom** (menu, on by default): the upper half of a key presses its top sensor,
  the lower half its bottom sensor. A TAP that lands on top of a HOLD in the same lane is played by
  holding one half and tapping the other, as on the cabinet.
- **Edge Assist** (on by default): a touch within 1/4 key of an edge also presses the neighbouring key.
- **Settings** (menu -> Settings): top/bottom boundary height, edge assist width, left/right margins
  (keys only span the inner area), air area height, a dead band between air and slider, touch highlight,
  row divider and LED brightness. Everything is saved and has a reset button.
- Every change sends one complete state built from all fingers, so a held finger never flickers off
  when another finger moves, lifts or touches the air area.

Fixes compared with upstream: only the bottom sensors (odd indices) were ever sent, so a second finger
or a tap on top of a hold on the same key never registered; partial states were sent while touches were
processed one by one (held lanes briefly released: dropped HOLDs, ghost TAPs); a finger lifting or touching
the air area cleared other fingers' lanes; the right-edge assist only worked on the left half of the slider.

`Tests/SliderMappingTests` checks the mapping (`swiftc -o t brokenithm-swiftui/Input/SliderMapping.swift Tests/SliderMappingTests/main.swift && ./t`).
`.github/workflows/build-ipa.yml` runs those tests and builds an unsigned IPA on every push.

## Setup

1. Make sure your PC and your iPhone or iPad are on the same Wi-Fi network.
2. Start the Brokenithm server on your PC alongside the game.
3. Open Brokenithm-SwiftUI. The status bar turns green once the PC connects.
4. Open the menu (the chevron in the top right) to enable **Air Input**, pick an air height, tap your card, or insert coins.

If the connection drops, choose **Restart Connection** from the menu. The app also reconnects on its own when you return to it.

## Tips

- Prop your device against the bottom of your monitor so the slider sits where the physical one would be.
- Turn off Auto-Lock while playing (Settings → Display & Brightness → Auto-Lock → Never).
- A 5 GHz Wi-Fi network or a phone-to-PC hotspot gives the lowest latency.

## Support

Found a bug or have an idea? [Open an issue](https://github.com/OWCramer/Brokenithm-SwiftUI/issues).

If you enjoy the app, you can support development on [Ko-fi](https://ko-fi.com/owen1218).

Made with ❤️ by [Owen Cramer](https://github.com/OWCramer/).
