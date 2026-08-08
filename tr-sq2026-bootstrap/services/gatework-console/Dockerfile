FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
RUN addgroup -S gatework && adduser -S gatework -G gatework
COPY --from=build --chown=gatework:gatework /app/.next/standalone ./
COPY --from=build --chown=gatework:gatework /app/.next/static ./.next/static
USER gatework
EXPOSE 3000

# ECS gives the task a hostname which resolves to its VPC address.  Next's
# standalone server would then bind only to that address, while the container
# health check intentionally uses loopback.  Bind explicitly to every
# interface so both the private Cloudflare sidecar and the loopback health
# probe always reach the same process.
CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]
