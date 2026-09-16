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

Made with ❤️ by [Owen Cramer](https://ocramer.com).
