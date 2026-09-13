#!/bin/bash

# Start virtual display (Xvfb)
Xvfb :99 -screen 0 ${SCREEN_SIZE} &
sleep 2

# Start lightweight window manager
openbox &

# Start VNC server (allows setup via remote desktop)
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw &

# Initialize Wine prefix if not created
if [ ! -d "$WINEPREFIX" ]; then
    wineboot --init
fi

# Run MT5 if installed, otherwise keep container active
if [ -f "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
else
    echo "MT5 not found. Use VNC on port 5900 or copy MT5 installer into container."
    tail -f /dev/null
fi