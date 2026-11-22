FROM node:22-alpine AS build
WORKDIR /app
COPY . .
RUN node scripts/build.mjs

FROM node:22-alpine
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4173
WORKDIR /app
COPY --from=build --chown=node:node /app/dist ./
USER node
EXPOSE 4173
CMD ["node", "server.mjs"]
