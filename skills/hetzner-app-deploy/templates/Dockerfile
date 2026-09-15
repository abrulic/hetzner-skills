FROM node:24-slim AS build
RUN corepack enable
WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm run build

FROM node:24-slim AS runtime
# Prisma probes for libssl at startup and warns (or picks the wrong engine) without it.
RUN apt-get update -y && apt-get install -y --no-install-recommends openssl \
	&& rm -rf /var/lib/apt/lists/*
RUN corepack enable
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
# pnpm-workspace.yaml carries pnpm 12's settings (saveExact, allowBuilds); the "pnpm"
# field in package.json and non-registry .npmrc keys are silently ignored without it.
COPY --from=build /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml /app/tsconfig.json ./
# Bake the pnpm binary named in `packageManager` into the image. Without this, every
# `db:deploy` on the deploy hot path fetches it from the npm registry first — slower, and
# a deploy that fails when the registry does.
RUN corepack install
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/prisma.config.ts ./
# Add further COPY lines if seed or migrate imports app source.
EXPOSE 3000
CMD ["node", "./build/server/index.js"]
