FROM python:3.12-alpine

RUN apk add --no-cache git curl bash procps lsof && \
    adduser -D -h /app kmacuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chown -R kmacuser:kmacuser /app

USER kmacuser

EXPOSE 7890
ENV KMAC_HOST=0.0.0.0
ENV KMAC_PORT=7890

CMD ["python3", "app.py"]
