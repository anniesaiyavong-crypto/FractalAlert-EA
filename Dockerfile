FROM ubuntu:22.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install Wine, Xvfb, Window Manager, VNC, and dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    gnupg2 \
    xvfb \
    x11vnc \
    openbox \
    wine64 \
    wine32 \
    winetricks \
    python3 \
    net-tools \
    && rm -rf /var/lib/apt/lists/*
# Install Python 3 and pip
RUN apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install MT5 Python bridge and analysis libraries
RUN pip3 install --no-cache-dir \
    MetaTrader5 \
    pandas \
    numpy \
    backtesting
    

# Set up environment variables
ENV DISPLAY=:99 \
    SCREEN_SIZE=1280x1024x24 \
    WINEPREFIX=/root/.wine \
    WINEARCH=win64

WORKDIR /root

# Startup script to launch Xvfb, VNC, and MT5
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5900

ENTRYPOINT ["/entrypoint.sh"]
