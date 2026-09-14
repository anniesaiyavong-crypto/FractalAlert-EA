#!/bin/bash


rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

# Start virtual display (Xvfb)
Xvfb :99 -screen 0 ${SCREEN_SIZE:-1280x1024x24} -ac +extension GLX +render -noreset &
XVFB_PID=$!

# Wait briefly for Xvfb to start
sleep 2

# Verify Xvfb is running
if ! ps -p $XVFB_PID > /dev/null; then
    echo "Xvfb failed to start!"
    exit 1
fi
# Start window manager
openbox &
sleep 1
# Start VNC server (bound to all interfaces)
x11vnc -display :99 -listen 0.0.0.0 -forever -shared -rfbport 5900 -nopw &

# Define default MT5 terminal path
MT5_PATH="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# Launch MT5 if installed, otherwise wait for setup
if [ -f "$MT5_PATH" ]; then
    echo "Starting MetaTrader 5..."
    wine "$MT5_PATH" /portable
else
    echo "MT5 terminal not found. Run mt5setup.exe via VNC first."
    tail -f /dev/null
fi