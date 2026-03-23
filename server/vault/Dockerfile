FROM alpine:3.19
RUN apk add --no-cache python3 py3-pip && \
    pip3 install --no-cache-dir --break-system-packages cryptography==44.0.0
RUN adduser -D -h /app vaultuser
COPY vault_server.py /app/vault_server.py
VOLUME /vault/data
RUN chown -R vaultuser:vaultuser /app
RUN mkdir -p /vault/data && chown -R vaultuser:vaultuser /vault/data
USER vaultuser
EXPOSE 9999
CMD ["python3", "/app/vault_server.py"]
