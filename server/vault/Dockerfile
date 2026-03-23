FROM alpine:3.19
RUN apk add --no-cache python3 py3-pip && \
    pip3 install --no-cache-dir --break-system-packages cryptography
COPY vault_server.py /app/vault_server.py
VOLUME /vault/data
EXPOSE 9999
CMD ["python3", "/app/vault_server.py"]
