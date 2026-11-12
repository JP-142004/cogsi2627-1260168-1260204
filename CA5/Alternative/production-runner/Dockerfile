FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv openssh-client \
    && rm -rf /var/lib/apt/lists/*
COPY --chmod=755 entrypoint.sh /usr/local/bin/ca5-runner
USER runner
ENTRYPOINT ["/usr/local/bin/ca5-runner"]
