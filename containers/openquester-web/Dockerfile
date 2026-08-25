FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

ARG OPENQUESTER_REF=f083d460f77adf3b5ec7a260cce124342c9844a1
ARG API_URL=/
ARG CLIENT_APP_URL=/

USER root

# Cirrus Labs does not publish a 3.44.2 image tag, but this OpenQuester
# revision requires that exact SDK release.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl git xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /opt/flutter \
    && mkdir -p /opt \
    && curl --fail --location --silent --show-error \
      https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.2-stable.tar.xz \
      | tar --extract --xz --file - --directory /opt

ENV PATH=/opt/flutter/bin:${PATH}

RUN flutter --version

WORKDIR /build

RUN git clone https://github.com/OpenQuester/OpenQuester.git /build/OpenQuester \
    && cd /build/OpenQuester \
    && git checkout "${OPENQUESTER_REF}"

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
