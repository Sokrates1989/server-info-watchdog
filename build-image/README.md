# 🏗️ Build Image

Scripts for building and pushing the Server Info Watchdog Docker image.

## 📋 Usage

### Linux/Mac
```bash
./build-image.sh
```

### Windows
```powershell
.\build-image.ps1
```

## 🔧 Process

The build script will:
1. Prompt for Docker image name and version
2. Build the Docker image from the project Dockerfile
3. Optionally push to a container registry
4. Update `.env` with the new image name/version

## 📦 Image Details

The built image contains:
- Python 3.9 base
- Server info monitoring logic
- Telegram notification support
- Threshold-based alerting

## 🚀 Deployment

After building and pushing the image, deploy to Docker Swarm using the [swarm-server-info-watchdog](https://github.com/Sokrates1989/swarm-server-info-watchdog) repository.
