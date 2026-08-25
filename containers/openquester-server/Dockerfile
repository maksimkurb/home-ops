FROM docker.io/library/node:24-alpine AS build

ARG OPENQUESTER_REF=f083d460f77adf3b5ec7a260cce124342c9844a1

RUN apk add --no-cache git \
    && git clone https://github.com/OpenQuester/OpenQuester.git /source \
    && cd /source \
    && git checkout "${OPENQUESTER_REF}"

WORKDIR /source/server

RUN npm ci \
    && npm run build

FROM docker.io/library/node:24-alpine

WORKDIR /app/server

COPY --from=build /source/server/package*.json ./
COPY --from=build /source/openapi/schema.json /app/openapi/schema.json
COPY --from=build /source/server/storage/ ./storage/
COPY --from=build /source/server/dist/ ./dist/

RUN npm ci --omit=dev

ENV NODE_ENV=production

EXPOSE 3000

CMD ["npm", "run", "start:prod"]
