QMX+ Configurator

Orignally developed as Windows GUI program developed Laurance Brungardt W5UW

Ported this program to run under MacOS and to access a Network Shared QMX/QMX+

Allows you to view and edit all the menu settings you would normally
have to access through PUTTY when you access a QRP-LABS QMX/QMX+ Radio.

Make a folder called QMX_Configurator copy
the files from the repository to that folder.


## Running on Windows

Requires Python 3.9 or newer from https://www.python.org/downloads/windows/
(tick "Add python.exe to PATH" in the installer).

* **Quick start:** double-click `qmx-run-win.cmd`. The first run creates a
  private `.venv-win` and installs PySide6 and pyserial; later runs start
  immediately. You can make a desktop shortcut to `qmx-run-win.cmd`.
* The radio appears as a COM port (e.g. `COM3`). Press **Refresh**, choose it
  and press **Connect**.
* For the shared QMX+ on the NAS, allow Python through Windows Defender
  Firewall when Windows asks (private networks).

## Running on macOS

Requires Python 3.9 or newer (`xcode-select --install` provides one, or use
python.org / Homebrew).

* **Quick start:** double-click `qmx-run-mac.command` (or run `./qmx-run-mac.command`
  in Terminal). The first run creates a private `.venv` and installs PySide6
  and pyserial; later runs start immediately (to open it from /Applications,
  see the next item). The program starts on its own and the Terminal window macOS
  opened for the script closes itself (the first time, allow Terminal to
  control Terminal). The window stays open only if something went wrong.
  Program output goes to `~/Library/Logs/QMX-Configurator.log`.
* **Add it to Applications:** copy `QMX+ Configurator.app` from the project
  folder to /Applications (and drag it to the Dock if you like). It starts the
  QMX+ Configurator in `~/src/QMX-Configurator` of whoever opens it, so the
  same app works on any Mac where the project is installed in that folder.
  * No Terminal window, except on the first run (or after requirements.txt
    changes), when it opens `qmx-run-mac.command` so the setup can be seen.
  * If the folder is missing or the program won't start, a dialog says why.
  * Once the app has been signed and notarized (next item), it opens on any
    Mac without a warning. An unsigned copy downloaded in a browser is blocked
    the first time: open **System Settings > Privacy & Security**, click
    **Open Anyway** next to the message about QMX+ Configurator, and confirm.
    (macOS 15 Sequoia and later no longer allow Control-click > Open for this.)
    A copy made with `git clone` is not blocked.

  If the project is somewhere other than `~/src/QMX-Configurator`, use an
  alias instead: select `qmx-run-mac.command`, choose **File > Make Alias**,
  name it `QMX+ Configurator` and copy it to /Applications.
* **Signing and notarizing the launcher app** (needs a paid Apple Developer
  account; done once, and again only when the app itself changes):
  1. Xcode > **Settings > Accounts** > your Apple ID > **Manage Certificates**
     > **+** > **Developer ID Application**.
  2. At account.apple.com, **Sign-In and Security > App-Specific Passwords**,
     create one, then store it for Apple's notarization tool:
     `xcrun notarytool store-credentials QMX-notary --apple-id <Apple ID> --team-id <Team ID>`
     (Team ID: developer.apple.com > Account > Membership details).
  3. Run `./qmx-sign-notarize-app.sh`. It builds the app's small compiled
     launcher (`launcher/qmx-launcher.c`, Apple silicon + Intel), signs the
     app with your Developer ID, sends it to Apple, staples Apple's ticket to
     it and checks it with Gatekeeper ("Notarized Developer ID").

  Run it again after changing `launcher/qmx-launcher.c` or anything inside
  the app (its `Contents/Resources/qmx-launcher.sh`, icon or Info.plist);
  changes to the Python program don't need it. Until the script has run, the
  app uses a small shell-script stand-in and works the same, just unsigned.
* **Standalone app:** run `./qmx-build-mac-app.sh`, then open
  `dist/QMX+Configurator.app` (drag it to /Applications if you like).

Connecting: plug in the QMX/QMX+ and press **Refresh**. It appears as
`/dev/cu.usbmodem…` (listed first). Only the `/dev/cu.*` form of each port is
shown, because opening `/dev/tty.*` can hang waiting for carrier detect. The
port box is editable, so you can also type a path the scan doesn't find,
such as a virtual port made by a network relay. If a port is reported busy,
close `screen`, CoolTerm or other radio software using it.

Snapshots and the pre-write backup default to your Documents folder.

## Shared QMX+ on a Synology NAS or Raspberry Pi (network)

The configurator can also reach a QMX+ that is shared over the network by the
relay from the QMX-Panadapter-NAS project (`tools/nas-relay/qmx_nas_relay.py`,
or the Raspberry Pi relay), the same relay the Tab5 panadapter uses.

1. On the radio: **System config > GPS & Ser. ports > USB serial ports = 3**.
   The relay gives PC software the radio's serial port 3 on **TCP 7356**.
2. Press **Find shared QMX**. It searches the network the same way as the
   Tab5's Find NAS (`QMXR?` broadcast on UDP 7355) and adds
   "Shared QMX+ on NAS <address>" to the Port list. Or type the NAS address
   (e.g. `10.0.0.137`) in the Port box.
3. Press **Connect**, then **Read all settings** as usual.

Notes:
* The last NAS address is remembered and listed on the next start.
* If the radio is off and the relay has the remote power cable set up, the
  configurator offers to turn it on (`PS1;`). The relay never lets `PS0;`
  (power off) through.
* QMX port 3 serves one PC program at a time. Stop the Mac TCI bridge or
  other software using TCP 7356 while configuring. The Tab5 stays connected.
* If DSM's firewall is on, allow UDP 7355 and TCP 7356. On macOS, allow the
  app (or Terminal/Python) under System Settings > Privacy & Security >
  Local Network.
