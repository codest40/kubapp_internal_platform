FROM python:3.11-slim

# ----------------------------
# Working directory
# ----------------------------
WORKDIR /app

# ----------------------------
# Accept build mode as argument
# ----------------------------
ARG BUILD_MODE=no-cache
ENV BUILD_MODE=${BUILD_MODE}

# ----------------------------
# Copy requirements first (for layer caching)
# ----------------------------
COPY ./app/requirements.txt ./requirements.txt

# ----------------------------
# Upgrade pip & install dependencies based on BUILD_MODE
# ----------------------------
RUN python -m pip install --upgrade pip setuptools wheel && \
    if [ "$BUILD_MODE" = "no-cache" ]; then \
        echo " Installing dependencies without cache"; \
        pip install --no-cache-dir -r requirements.txt; \
    else \
        echo " Installing dependencies with cache"; \
        pip install -r requirements.txt; \
    fi

# ----------------------------
# Copy application code
# ----------------------------
COPY ./app /app

#ARG SERVICE_NAME=weather_app
# ----------------------------
# Ensure entrypoint is executable
# ----------------------------
RUN chmod +x entrypoint.sh

# ----------------------------
# Entrypoint
# ----------------------------
CMD ["./entrypoint.sh"]
