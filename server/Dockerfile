FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl bash procps lsof \
    unixodbc-dev odbcinst \
    gnupg build-essential python3-dev \
    python3-pyodbc \
    && rm -rf /var/lib/apt/lists/*

# Install Microsoft ODBC Driver for SQL Server
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /app kmacuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-deps aiohttp requests

COPY . .
RUN chown -R kmacuser:kmacuser /app && \
    chmod +x /app/docker-entrypoint.sh

EXPOSE 7890
ENV KMAC_HOST=0.0.0.0
ENV KMAC_PORT=7890

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["python3", "app.py"]
