FROM nousresearch/hermes-agent:latest

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && gh --version \
  && rm -rf /var/lib/apt/lists/*
