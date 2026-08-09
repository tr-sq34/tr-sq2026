FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
# Read at runtime by `npm run migrate`; migrate.ts resolves ../migrations
# relative to its own compiled location.
COPY migrations ./migrations
USER node
EXPOSE 8080
# The projection worker ships in the same image and is selected by overriding
# this command in the worker container app, so both always run identical code
# and share one event contract.
CMD ["node", "--enable-source-maps", "dist/server.js"]
