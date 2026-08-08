FROM node:22-bookworm-slim AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
COPY migrations ./migrations
RUN npm run build
# Pin the source to the Azure Database for PostgreSQL root CA (DigiCert Global Root G2); the bundle is copied into
# the final image so database TLS verification also works in private subnets.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && mkdir -p /app/certs \
    && curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem \
      --output /app/certs/azure-postgres-root.pem \
    && test -s /app/certs/azure-postgres-root.pem \
    && rm -rf /var/lib/apt/lists/*

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/migrations ./migrations
COPY --from=build /app/certs ./certs
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
