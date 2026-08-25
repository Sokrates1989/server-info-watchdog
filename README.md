# serverStateChecker
Check the state of servers by text files they write themselves.

# Understanding
The servers create a file with linux server status client https://github.com/Sokrates1989/linux-server-status.git using --json option

The file / the directory of this file are being mapped as volumes to this image. That way this tool gets information about the server.

This image/container (serverStateChecker) should also be created/executed on a similar schedule as the servers cron.

The tool writes regular information into configured Telegram chats or groups.
When thresholds are exceeded, separate Telegram destinations and notification
frequencies can increase the visibility of warning and error messages.
Telegram is currently the only delivery transport. Email and SMTP configuration
are not implemented by the watchdog backend or its administration UI.

# Environment Vars
Pass warning and error limits/ thresholds based on the servers capabilities and your requirments in percentages.

## Quick Start Shortcuts

The numbered quick-start options remain supported. Press `p` to build and
publish all Docker images or `b` to run Keycloak bootstrap directly.


# Push image to dockerhub

```bash
docker image ls sokrates1989/server-state-checker
```

```bash
docker build -t server-state-checker .
docker tag server-state-checker sokrates1989/server-state-checker:latest
docker tag server-state-checker sokrates1989/server-state-checker:major.minor.patch
docker login
docker push sokrates1989/server-state-checker:latest
docker push sokrates1989/server-state-checker:major.minor.patch
docker image ls sokrates1989/server-state-checker
git status

```
## Debug images

### Create

```bash
docker build -t server-state-checker .
docker tag server-state-checker sokrates1989/server-state-checker:DEBUGmajor.minor.patch
docker login
docker push sokrates1989/server-state-checker:DEBUGmajor.minor.patch
docker image ls sokrates1989/server-state-checker
git status

```
### Cleanup / Delete
```bash
docker rmi sokrates1989/server-state-checker:DEBUGmajor.minor.patch
```


