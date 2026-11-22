#!/bin/bash
# QMX+ Configurator launcher app (Contents/Resources/qmx-launcher.sh).
# Run by the app's main program, Contents/MacOS/qmx-launcher. After editing this
# file, run qmx-sign-notarize-app.sh again: signing seals it.
# Starts the QMX+ Configurator installed in ~/src/QMX-Configurator of whoever
# runs it, so the same app works on any Mac with the files in that folder.
# Copy "QMX+ Configurator.app" to /Applications (or the Dock).
#
#  * First run (no Python environment yet): opens qmx-run-mac.command in
#    Terminal so the setup can be seen; it starts the program and closes itself.
#  * Otherwise: starts the program directly, with no Terminal window.
#  * Problems are shown in a dialog. Program output goes to
#    ~/Library/Logs/QMX-Configurator.log.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
DIR="$HOME/src/QMX-Configurator"
LOG="$HOME/Library/Logs/QMX-Configurator.log"

alert() {
  osascript -e 'on run argv' \
            -e 'display alert "QMX+ Configurator" message (item 1 of argv) as critical' \
            -e 'end run' "$1" >/dev/null 2>&1
}

if [ ! -f "$DIR/qmx_configurator.py" ]; then
  alert "The QMX+ Configurator files were not found in ~/src/QMX-Configurator.

Put the project folder there (it must contain qmx_configurator.py and qmx-run-mac.command), then open this app again."
  exit 1
fi

if [ ! -x "$DIR/.venv/bin/python" ] || [ "$DIR/requirements.txt" -nt "$DIR/.venv/.installed" ]; then
  # First run or new requirements: let the Terminal launcher do the setup,
  # where its progress and any errors can be seen.
  if [ -f "$DIR/qmx-run-mac.command" ]; then
    open "$DIR/qmx-run-mac.command"
  else
    alert "Setup is needed, but qmx-run-mac.command is missing from ~/src/QMX-Configurator."
    exit 1
  fi
  exit 0
fi

cd "$DIR" || exit 1
mkdir -p "$(dirname "$LOG")"
"$DIR/.venv/bin/python" qmx_configurator.py </dev/null >"$LOG" 2>&1 &
PID=$!
sleep 2
if ! kill -0 "$PID" 2>/dev/null; then
  alert "QMX+ Configurator stopped right after starting.

$(tail -n 12 "$LOG")

Full output: ~/Library/Logs/QMX-Configurator.log"
  exit 1
fi
exit 0
