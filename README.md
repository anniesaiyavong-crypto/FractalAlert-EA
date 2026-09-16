
# Headless Metatrader 5 

This guide shows how to set up MetaTrader 5 and run an EA headlessly inside a local or cloud machine using Docker
System Requirement:
RAM: 1GB minimum.

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

## Directory overview
```
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
└── mt5_data/             <-- Wine directory (contains MT5, EAs, & configs)
```
## Copy the EA file to the MT5 Experts folder
```bash
sudo chown -R $USER:$USER mt5_data
cp FractalAlert.mq5 mt5_data/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/
docker exec -u root mt5_headless chown -R root:root /root/.wine
```
# Compile the EA using MetaEditor
This process can be done by the MetaEditor GUI

## Telegram Alert Configuration

### 1. Enable WebRequest in MetaTrader 5

Allow the Expert Advisor to send HTTP requests to the Telegram API:

1. Open MT5 and navigate to **Tools** -> **Options** (or press `Ctrl+O`).
2. Switch to the **Experts** tab.
3. Check **Allow WebRequest for listed URL:**.
4. Add the Telegram API URL:

```text
https://api.telegram.org
```

> [!NOTE]
> MT5 will block outbound HTTPS requests if this URL is not explicitly whitelisted.

### 2. Configure EA Input Parameters

Attach the Expert Advisor to a chart, open the **Inputs** tab, and enter your Telegram credentials:

| Parameter | Type | Description | Source / Format |
| :--- | :--- | :--- | :--- |
| `InpTelegramToken` | String | Bot Authentication Token | Created via `@BotFather` |
| `InpTelegramChatID` | String | Telegram User or Group Chat ID | Numeric ID (e.g. `123456789` or `-100...`) |