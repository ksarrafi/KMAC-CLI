# KMac Tron — Iso sandbox (CI-parity tools + workspace at /workspace)
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq python3 python3-pip \
    shellcheck rsync file ripgrep \
    && rm -rf /var/lib/apt/lists/*

COPY iso-entry.sh /usr/local/bin/iso-entry
RUN chmod +x /usr/local/bin/iso-entry

WORKDIR /workspace
LABEL org.kmac.tron.iso="2"
ENTRYPOINT ["/usr/local/bin/iso-entry"]
