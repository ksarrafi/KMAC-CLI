# KMac Tron — Iso sandbox image (deterministic tools; workspace mounted at /workspace)
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY iso-entry.sh /usr/local/bin/iso-entry
RUN chmod +x /usr/local/bin/iso-entry

WORKDIR /workspace
LABEL org.kmac.tron.iso="1"
ENTRYPOINT ["/usr/local/bin/iso-entry"]
