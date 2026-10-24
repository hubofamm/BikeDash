# Bike Dash iPhone app

Turn-by-turn directions (Apple Maps routing) sent to the Bike Dash ESP32 board over Bluetooth.

## Build (no Mac needed)
1. Upload everything in this folder to a GitHub repository (keep the `.github` folder).
2. Open the repo's **Actions** tab. The "Build iPhone app" workflow runs on every push
   (or press **Run workflow**).
3. When it's green, open the run and download **BikeDash-ipa** (a zip with `BikeDash.ipa`).

## Install on the iPhone (Windows)
1. Install **iTunes** (from apple.com, not the Microsoft Store version) and **Sideloadly** (sideloadly.io).
2. Connect the iPhone by USB, tap **Trust** on the phone.
3. Drag `BikeDash.ipa` into Sideloadly, enter your Apple ID, press **Start**.
4. On the iPhone: Settings > General > VPN & Device Management > your Apple ID > **Trust**.
5. Settings > Privacy & Security > **Developer Mode** > on (iPhone restarts).
With a free Apple ID the app stops opening after 7 days: just repeat step 3.

## Use
- Board must run `bike_dashboard_nav.ino` and be paired with the iPhone.
- Open Bike Dash: the dot turns green when it finds the board. Press **Test** to check.
- Search a place, tap it, ride. The phone can be locked.

## Packet format (app -> board)
`maneuver|metersToTurn|instruction|street|ETA|remainingMeters|remainingMinutes`, or `X` to stop.
Maneuver: 0 straight, 1 left, 2 right, 3 slight left, 4 slight right, 5 sharp left,
6 sharp right, 7 U-turn, 8 roundabout, 9 arrive.
