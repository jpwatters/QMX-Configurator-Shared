#!/bin/bash
# Builds "QMX+Configurator.app" in ./dist using PyInstaller.
# Copy the app to /Applications afterwards if you like.
set -e
cd "$(dirname "$0")"
PY="$(command -v python3)"
[ -x .venv/bin/python ] || "$PY" -m venv .venv
.venv/bin/python -m pip install --upgrade pip >/dev/null
.venv/bin/python -m pip install -r requirements.txt pyinstaller
touch .venv/.installed
rm -rf build "dist/QMX+Configurator.app" "dist/QMX+Configurator"
.venv/bin/pyinstaller --noconfirm --windowed \
  --name "QMX+Configurator" \
  --osx-bundle-identifier com.kc9kko.qmxconfigurator \
  --hidden-import qmx_editing --hidden-import qmx_protocol \
  qmx_configurator.py
# macOS asks before an app talks to the local network (needed for the NAS relay).
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'QMX+ Configurator connects to a QMX+ shared from your NAS over the local network.'" \
  "dist/QMX+Configurator.app/Contents/Info.plist" 2>/dev/null || true
# Ad-hoc sign so Gatekeeper lets it launch locally (Apple Silicon requires a signature).
codesign --force --deep --sign - "dist/QMX+Configurator.app"
echo
echo "Built: $(pwd)/dist/QMX+Configurator.app"
