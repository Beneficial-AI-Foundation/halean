# The Lean automation service + its bridge, as one container.
# Build context is the repository root (see demo/docker-compose.yml).

# --- 1. build the Lean engine for Linux -------------------------------------
FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git build-essential \
 && apt-get clean
RUN curl -sSfL --retry 5 --retry-all-errors https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | sh -s -- -y --default-toolchain none
ENV PATH=/root/.elan/bin:$PATH
WORKDIR /src
COPY lean-toolchain lakefile.toml lake-manifest.json ./
RUN elan toolchain install "$(cat lean-toolchain)"
COPY HALean.lean ./
COPY HALean ./HALean
COPY Exe ./Exe
RUN lake build halean-automation

# --- 2. runtime: engine binary + Python bridge -------------------------------
FROM python:3.13-slim-bookworm
RUN pip install --no-cache-dir "websockets>=13" pyyaml
COPY --from=build /src/.lake/build/bin/halean-automation /usr/local/bin/halean-automation
COPY bridge/bridge.py bridge/protocol.py /app/bridge/
COPY demo/setup.py demo/simulator.py demo/automations.yaml /app/demo/
ENV HALEAN_ENGINE=/usr/local/bin/halean-automation PYTHONUNBUFFERED=1
WORKDIR /app
CMD ["python", "demo/setup.py", "--then-bridge"]
