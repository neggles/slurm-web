# Slurm-web Container Image
#
# Multi-stage build for Slurm-web gateway and agent components.
# Includes frontend assets built from source.
#
# Usage:
#   docker build -t slurm-web:latest .
#   docker run -e SLURM_WEB_MODE=gateway -p 5011:5011 slurm-web:latest
#   docker run -e SLURM_WEB_MODE=agent -p 5012:5012 slurm-web:latest
#
# Environment Variables:
#   SLURM_WEB_MODE: Set to "gateway" or "agent" to select component
#
# Configuration:
#   Mount config files to /etc/slurm-web/gateway.ini or /etc/slurm-web/agent.ini
#   Mount JWT key to /var/lib/slurm-web/jwt.key

# base image tags to use
ARG PYTHON_VERSION=3.11-slim
ARG NODE_VERSION=20-slim

# settings for apt and pip (inheritable by all images)
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBIAN_PRIORITY="critical"
ARG PIP_PREFER_BINARY="1"
ARG SLURM_WEB_VERSION="6.0.0"

# Stage 1: Build frontend assets
FROM node:${NODE_VERSION} AS frontend-builder

# silence npm audit and funding messages
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_FUND=false

# Copy frontend source and assets into the build stage
COPY . /app/

# Set working directory for frontend build
WORKDIR /app/frontend

# Install dependencies and build frontend assets
RUN npm ci && npm run build-only


# Stage 2: Build Python wheel
FROM python:${PYTHON_VERSION} AS python-builder

# set shell
SHELL ["/bin/bash", "-ceuxo", "pipefail"]

# Inherit args from global
ARG DEBIAN_FRONTEND
ARG DEBIAN_PRIORITY
ARG PIP_PREFER_BINARY

# make pip stop complaining about being root
ENV PIP_ROOT_USER_ACTION="ignore"
ENV _PIP_LOCATIONS_NO_WARN_ON_MISMATCH="1"

# copy source code into the build stage
COPY . /app/
# set the working directory
WORKDIR /app

# Build the application wheel
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    python -m pip install build \
    && python -m build --wheel

# Print the generated wheel files for debugging purposes
RUN ls -l /app/dist/*.whl


# Stage 3: Final runtime image
FROM python:${PYTHON_VERSION} AS app

LABEL org.opencontainers.image.title="Slurm-web"
LABEL org.opencontainers.image.description="Web dashboard for Slurm HPC clusters"
LABEL org.opencontainers.image.url="https://github.com/rackslab/Slurm-web"
LABEL org.opencontainers.image.source="https://github.com/rackslab/Slurm-web"
LABEL org.opencontainers.image.licenses="MIT,GPL-3.0"

# set shell
SHELL ["/bin/bash", "-ceuxo", "pipefail"]

# Inherit args from global
ARG DEBIAN_FRONTEND
ARG DEBIAN_PRIORITY
ARG PIP_PREFER_BINARY
ARG SLURM_WEB_VERSION

# make pip stop complaining about being root
ENV PIP_ROOT_USER_ACTION="ignore"
ENV _PIP_LOCATIONS_NO_WARN_ON_MISMATCH="1"

# Install runtime dependencies
# - GTK/Pango libraries for RacksDB infrastructure visualization
# - LDAP libraries for authentication support
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get -y update \
    && apt-get install -y --no-install-recommends \
        gcc \
        pkg-config \
        libcairo2-dev \
        libgirepository-2.0-dev \
        gir1.2-glib-2.0 \
        gir1.2-pango-1.0 \
        gir1.2-pangocairo-1.0 \
        python3-gi \
        python3-gi-cairo \
        libldap2-dev \
        libsasl2-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set working directory for runtime
WORKDIR /app

# Copy built artifacts from previous stages
COPY --from=frontend-builder /app/frontend/dist /usr/share/slurm-web/frontend
COPY --from=python-builder /app/conf/vendor /usr/share/slurm-web/conf

# Install Slurm-web with all optional dependencies
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    --mount=type=bind,from=python-builder,source=/app/dist,target=/app/dist \
    python -m pip install "/app/dist/slurm_web-${SLURM_WEB_VERSION}-py3-none-any.whl[gateway,agent]"

# Ensure required directories exist for config and runtime data
RUN mkdir -p /etc/slurm-web /var/lib/slurm-web

# Copy entrypoint script
COPY ./docker/entrypoint.sh /app/entrypoint.sh
RUN chmod a+x /app/entrypoint.sh

# add a persistent volume for JWT keys and other runtime data
VOLUME ["/etc/slurm-web"]

ENTRYPOINT ["/app/entrypoint.sh"]
