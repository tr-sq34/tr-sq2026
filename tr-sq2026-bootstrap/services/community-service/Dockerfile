FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
COPY migrations ./migrations
# Acilis kartlarinin gorselleri: uye medyasi degil, servisin kendi sundugu dort
# dosya. Imajda olmazlarsa serit cizilir ama kartlar bos kare olur.
COPY assets ./assets
RUN npm run build
# The container runs in private subnets, but PostgreSQL TLS is still verified
# against AWS' RDS trust store. The public CA bundle is copied into the final
# image; no credential is embedded in an image layer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && mkdir -p /app/certs \
    && curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
      --output /app/certs/rds-global-bundle.pem \
    && test -s /app/certs/rds-global-bundle.pem \
    && rm -rf /var/lib/apt/lists/*

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY --from=build /app/migrations ./migrations
COPY --from=build /app/assets ./assets
COPY --from=build /app/certs ./certs
USER node
EXPOSE 8081
CMD ["node", "dist/server.js"]
