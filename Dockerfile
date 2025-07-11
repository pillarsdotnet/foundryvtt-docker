ARG BUN_DISTRO=oven/bun:alpine

FROM ${BUN_DISTRO}

ARG FOUNDRY_RELEASE_URL
ARG FOUNDRY_VERSION=13.346
ARG CONTAINER_VERSION=${FOUNDRY_VERSION}.0

ENV ARCHIVE="foundryvtt-${FOUNDRY_VERSION}.zip"
ENV FOUNDRY_VERSION=${FOUNDRY_VERSION}
ENV HOME=/home/bun

LABEL com.foundryvtt.version=${FOUNDRY_VERSION}
LABEL org.opencontainers.image.authors="pillarsdotnet@gmail.com"
LABEL org.opencontainers.image.vendor="pillarsdotnet"

WORKDIR ${HOME}

COPY \
  *.json \
  src/*.sh \
  src/*.ts \
  ./

RUN mkdir -p resources /data && \
  chmod a+rwx resources /data  && \
  apk update && \
  apk add --no-cache \
    bash \
    curl \
    file \
    jq \
    patch \
    sed \
    tzdata \
    unzip \
    util-linux \
    wget && \
  echo ${CONTAINER_VERSION} > image_version.txt

USER bun

RUN \
  --mount=type=secret,id=foundry_username,required=false \
  --mount=type=secret,id=foundry_password,required=false \
  bun install && \
  if [ -f /run/secrets/foundry_username ] && [ -f /run/secrets/foundry_password ]; then \
    ./authenticate.ts \
      "$(cat /run/secrets/foundry_username)" \
      "$(cat /run/secrets/foundry_password)" \
      cookiejar.json && \
    presigned_url=$( \
      ./get_release_url.ts \
        --retry 5 \
	cookiejar.json \
	"${FOUNDRY_VERSION}" \
    ) && \
    DOWNLOAD_URL="${presigned_url}"; \
  elif [ -n "${FOUNDRY_RELEASE_URL}" ]; then \
    DOWNLOAD_URL="${FOUNDRY_RELEASE_URL}"; \
  else \
    echo "No valid credentials or pre-signed URL provided. \
      Skipping pre-installation."; \
  fi && \
  if [ -n "${DOWNLOAD_URL}" ]; then \
    wget -O ${ARCHIVE} "${DOWNLOAD_URL}" && \
    mkdir -p "dist/resources/app" && \
    unzip -d "dist/resources/app" ${ARCHIVE}; \
  fi

VOLUME ["/data"]

# HTTP Server
EXPOSE 30000/TCP

ENTRYPOINT ["./entrypoint.sh"]
CMD ["resources/app/main.mjs", \
  "--port=30000", \
  "--headless", \
  "--noupdate", \
  "--dataPath=/data"]
HEALTHCHECK \
  --start-period=3m \
  --interval=30s \
  --timeout=5s \
  CMD ./check_health.sh
