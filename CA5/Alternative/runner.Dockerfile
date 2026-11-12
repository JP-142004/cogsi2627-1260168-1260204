FROM node:24-bookworm-slim AS node
FROM cogsi-ca5-jenkins:local
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip xz-utils python3-pip \
    && rm -rf /var/lib/apt/lists/*
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
ENV AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ENTRYPOINT []
CMD ["bash"]
