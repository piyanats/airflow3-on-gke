# Custom Airflow 3 Image with Additional Dependencies using UV Package Manager
# UV is a fast Python package installer written in Rust (10-100x faster than pip)

FROM apache/airflow:3.0.0-python3.12

# Metadata
LABEL maintainer="your-email@example.com"
LABEL description="Custom Apache Airflow 3 with additional dependencies installed via UV"
LABEL version="3.0.0-custom-v1"

# Switch to root user to install system packages
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    gcc \
    g++ \
    make \
    # Database clients (optional)
    postgresql-client \
    # Libraries for Python packages
    libpq-dev \
    libssl-dev \
    libffi-dev \
    # Utilities
    curl \
    wget \
    git \
    vim \
    # Clean up
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install UV - Fast Python package installer
# UV is 10-100x faster than pip and pip-compatible
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Add UV to PATH
ENV PATH="/root/.cargo/bin:$PATH"

# Switch back to airflow user for security
USER airflow

# Add UV to airflow user PATH
ENV PATH="/home/airflow/.cargo/bin:$PATH"

# Set working directory
WORKDIR /opt/airflow

# Copy requirements file
COPY --chown=airflow:root requirements.txt /tmp/requirements.txt

# Install Python dependencies using UV
# UV is much faster than pip and handles dependency resolution better
# UV was already installed as root user above
RUN /home/airflow/.cargo/bin/uv pip install --system -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Optional: Copy custom plugins
# COPY --chown=airflow:root plugins/ ${AIRFLOW_HOME}/plugins/

# Optional: Copy DAGs (not recommended - use Git-Sync or PVC instead)
# COPY --chown=airflow:root dags/ ${AIRFLOW_HOME}/dags/

# Optional: Copy custom configuration
# COPY --chown=airflow:root config/airflow.cfg ${AIRFLOW_HOME}/airflow.cfg

# Verify installations
RUN python -c "import pandas; print(f'✓ Pandas version: {pandas.__version__}')" && \
    python -c "import google.cloud.storage; print('✓ Google Cloud Storage: OK')" && \
    python -c "import requests; print('✓ Requests: OK')"

# Set environment variables if needed
# ENV PYTHONPATH="${PYTHONPATH}:/opt/airflow/plugins"

# The base image already sets the correct entrypoint and CMD
