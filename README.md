
# Headless Trading Bot Setup

This guide explains how to set up MetaTrader 5 and run a trading bot headlessly inside local/cloud machine using Docker.

## Build and run

```bash
docker compose build
docker compose up -d
```

The container is named `mt5_headless` and exposes the VNC server on port `5900`.

## Install MetaTrader 5

Open a shell inside the running container:

```bash
docker exec -it mt5_headless bash
```

Download the MT5 installer:

```bash
wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe
```

Start the installer with Wine:

```bash
DISPLAY=:99 wine /tmp/mt5setup.exe
```

## Finish setup through VNC

Connect to the VNC server with a VNC client to complete the MetaTrader 5 setup wizard.


To stop the container:

```bash
docker compose down
```

├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── app/                  <-- Python scripts & CSV data 
│   ├── download_data.py
│   ├── backtest.py
│   └── main_bot.py
└── mt5_data/             <-- Wine directory (auto-managed by Docker volume)