# PYTHON.
FROM python:3.9

# Enable Virtual Environment.
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip, install and upgrade pip dependencies.
COPY docker/pip_install.txt docker/pip_upgrade.txt /code/
WORKDIR /code
RUN python3 -m venv $VIRTUAL_ENV \
    && python -m pip install --upgrade pip \
    && pip install --upgrade pip \
    && pip install -r pip_install.txt \
    && pip install -r pip_upgrade.txt --upgrade \
    && rm -rf /root/.cache/pip

# Copy the app.
COPY . /code

# Remove unwanted files or directories (but keep /code/docker for entrypoint).
RUN rm -rf \
    /code/.git \
    /code/.idea \
    /code/config/config.txt \
    /code/logs \
    /code/serverInfo \
    /code/docker-compose.yml \
    && mkdir -p /code/logs/dayBased \
    && mkdir -p /code/serverInfo \
    && chmod 755 /code/docker/entrypoint.sh || true

# Configure entrypoint that generates config from environment; the actual
# command (python src/check_server.py) is provided by docker-compose.
ENTRYPOINT ["/code/docker/entrypoint.sh"]