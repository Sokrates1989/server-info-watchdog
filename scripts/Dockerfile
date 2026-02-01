FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY keycloak_bootstrap.py .
CMD ["python", "keycloak_bootstrap.py"]
