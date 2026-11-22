#!/bin/bash
# QMX+ Configurator launcher for macOS. Double-click in Finder or run from Terminal.
# First run creates a private Python environment (.venv) and installs PySide6 + pyserial.
set -e
cd "$(dirname "$0")"

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "python3 not found. Install it with:  xcode-select --install"
  echo "or from https://www.python.org/downloads/macos/ (or: brew install python)"
  read -n1 -rp "Press any key to close..."; exit 1
fi

if [ ! -x .venv/bin/python ] || [ requirements.txt -nt .venv/.installed ]; then
  echo "Setting up Python environment (first run only)..."
  "$PY" -m venv .venv
  .venv/bin/python -m pip install --upgrade pip >/dev/null
  .venv/bin/python -m pip install -r requirements.txt
  touch .venv/.installed
fi

exec .venv/bin/python qmx_configurator.py "$@"
