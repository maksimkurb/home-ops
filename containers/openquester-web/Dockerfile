FROM docker.io/library/ubuntu:24.04 AS build

ARG OPENQUESTER_REF=f083d460f77adf3b5ec7a260cce124342c9844a1
ARG API_URL=/
ARG CLIENT_APP_URL=/

USER root

# Install the exact SDK required by the pinned OpenQuester revision.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      ca-certificates curl git libglu1-mesa unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt \
    && curl --fail --location --silent --show-error \
      https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.2-stable.tar.xz \
      | tar --extract --xz --file - --directory /opt

ENV PATH=/opt/flutter/bin:/root/.pub-cache/bin:${PATH}

RUN git config --system --add safe.directory /opt/flutter \
    && flutter --version

WORKDIR /build

COPY runtime-origin.patch /tmp/runtime-origin.patch

RUN git clone https://github.com/OpenQuester/OpenQuester.git /build/OpenQuester \
    && cd /build/OpenQuester \
    && git checkout "${OPENQUESTER_REF}" \
    && git apply /tmp/runtime-origin.patch

WORKDIR /build/OpenQuester/client

RUN printf '%s\n' \
      "API_URL=${API_URL}" \
      "CLIENT_APP_URL=${CLIENT_APP_URL}" \
      'DISCORD_AUTH_CLIENT_ID=' > apps/client/.env \
    && flutter pub get \
    && dart pub global activate melos \
    && melos bootstrap \
    && melos run pre_build \
    && cd apps/client \
    && flutter build web --no-web-resources-cdn --wasm

FROM docker.io/library/nginx:1.27.5-alpine

COPY --from=build /build/OpenQuester/client/apps/client/build/web/ /usr/share/nginx/html/
