#!/bin/bash


rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

# Start virtual display (Xvfb)
Xvfb :99 -screen 0 1280x1024x24 -ac +extension GLX +render -noreset &
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

# Start VNC server (bound to all interfaces)
x11vnc -display :99 -listen 0.0.0.0 -forever -shared -rfbport 5900 -nopw &

# Keep container alive if MT5 isn't launched yet
tail -f /dev/null