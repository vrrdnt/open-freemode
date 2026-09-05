FROM node:22-trixie-slim@sha256:7b8a0c89c54499bee567618f96578e1a12a800f062fbdbfd1fb6a443fa6f6284 AS build
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY lib/ lib/
COPY resources/ resources/
COPY scripts/build.mjs scripts/build.mjs
RUN npm run build && npm prune --omit=dev --ignore-scripts

FROM node:22-trixie-slim@sha256:7b8a0c89c54499bee567618f96578e1a12a800f062fbdbfd1fb6a443fa6f6284
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates tini \
    && rm -rf /var/lib/apt/lists/* \
    && usermod --login container --home /home/container node \
    && groupmod --new-name container node \
    && mkdir -p /home/container && chown container:container /home/container
WORKDIR /opt/open-freemode
COPY runtime.lock.json ./
COPY scripts/fetch-runtime.py scripts/fetch-runtime.py
RUN python3 scripts/fetch-runtime.py runtime.lock.json runtime
COPY --from=build /build/build/resources resources/
COPY --from=build /build/node_modules node_modules/
COPY package.json package-lock.json LICENSE ./
COPY lib/ lib/
COPY scripts/launcher.py scripts/migrate.mjs scripts/
RUN chmod -R a+rX /opt/open-freemode
USER container
ENV HOME=/home/container
WORKDIR /home/container
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python3", "/opt/open-freemode/scripts/launcher.py"]
