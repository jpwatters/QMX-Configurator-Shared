#!/bin/bash
# QMX+ Configurator launcher for macOS. Double-click it in Finder (or an alias
# to it, e.g. in /Applications), or run it from Terminal.
# The first run creates a private Python environment (.venv) and installs
# PySide6 + pyserial. The program is then started on its own, and the Terminal
# window that macOS opened for this script closes itself. It stays open only
# if something goes wrong, so you can read why.
# Program output goes to ~/Library/Logs/QMX-Configurator.log.
set -e
cd "$(dirname "$0")"

fail() { echo; echo "$1"; read -n1 -rp "Press any key to close..."; exit 1; }

PY="$(command -v python3 || true)"
[ -n "$PY" ] || fail "python3 not found. Install it with:  xcode-select --install
or from https://www.python.org/downloads/macos/ (or: brew install python)"

if [ ! -x .venv/bin/python ] || [ requirements.txt -nt .venv/.installed ]; then
  echo "Setting up the Python environment (first run only)..."
  "$PY" -m venv .venv || fail "Could not create the Python environment."
  .venv/bin/python -m pip install --upgrade pip >/dev/null
  .venv/bin/python -m pip install -r requirements.txt || fail "Installing PySide6/pyserial failed (check the internet connection)."
  touch .venv/.installed
fi

# Start the program in its own session, detached from this Terminal window,
# so closing the window doesn't close (or ask about) the program.
LOG="$HOME/Library/Logs/QMX-Configurator.log"
mkdir -p "$(dirname "$LOG")"
PID=$(.venv/bin/python -c '
import subprocess, sys
p = subprocess.Popen([sys.executable, "qmx_configurator.py", *sys.argv[2:]],
                     stdin=subprocess.DEVNULL, stdout=open(sys.argv[1], "w"),
                     stderr=subprocess.STDOUT, start_new_session=True)
print(p.pid)' "$LOG" "$@")
sleep 2
if ! kill -0 "$PID" 2>/dev/null; then
  echo "QMX+ Configurator stopped right after starting. Its output:"
  echo "----"; cat "$LOG"; echo "----"
  fail "(also saved in $LOG)"
fi

# Close the Terminal window macOS opened for this script. Only a window that
# Finder opened (its command line ends in "; exit;") is closed, never a
# Terminal window you typed the command into. The close runs a moment after
# this script has ended, so Terminal has nothing running to ask about.
TTY=$(tty 2>/dev/null || true)
if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ] && [ -n "$TTY" ] && [ "$TTY" != "not a tty" ]; then
  CLOSE='on run argv
  set myTTY to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is myTTY then
          if (history of t) contains "; exit;" then close w
          if (count of windows) is 0 then quit
          return
        end if
      end repeat
    end repeat
  end tell
end run'
  .venv/bin/python -c '
import subprocess, sys
subprocess.Popen(["/bin/sh", "-c", "sleep 1; exec /usr/bin/osascript -e \"$1\" \"$2\"", "sh",
                  sys.argv[1], sys.argv[2]],
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                 stderr=subprocess.DEVNULL, start_new_session=True)' "$CLOSE" "$TTY"
fi
exit 0
