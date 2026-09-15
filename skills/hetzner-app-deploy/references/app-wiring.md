# App wiring

The `templates/` files are whole-file copies. This is the other half: edits to files the
app **already has**. A bare systems-pro base template has no Prisma at all, so
`pnpm run db:deploy` — which the deploy workflow depends on — does not exist until these
are done.

The versions below are a known-good set, verified end to end against a real deploy.
Prefer matching them over `@latest` while Prisma 8 is still RC.

## 1. Dependencies

```bash
pnpm add @prisma/adapter-pg@7.9.1 @prisma/client@7.9.1 pg@8.23.0
pnpm add -D prisma@7.9.1
```

`pg` is a peer of the adapter and is never imported directly. No `@types/pg` — the
adapter ships its own.

## 2. `pnpm-workspace.yaml`

pnpm 12 fails the install rather than silently skipping a build script, so Prisma must be
allowed to place its engines:

```yaml
allowBuilds:
  "@prisma/client": true
  "@prisma/engines": true
  prisma: true
```

If the app has no `pnpm-workspace.yaml`, it is on older pnpm and this step does not apply.

## 3. `package.json`

```jsonc
"db:generate": "prisma generate",
"db:migrate":  "prisma migrate dev",
"db:deploy":   "prisma migrate deploy",
"db:reset":    "prisma migrate reset",
"db:studio":   "prisma studio",
"postinstall": "pnpm run typegen && pnpm run db:generate"
```

`db:deploy` is the name the deploy workflow calls — do not rename it.

The generated client is gitignored, so `postinstall` is load-bearing: without it a fresh
clone cannot typecheck.

Dev and start need `.env` loaded into `process.env`, because the env schema now validates
`DATABASE_URL`:

```jsonc
"dev":   "dotenvx run --quiet -- react-router dev",
"start": "NODE_ENV=production dotenvx run --quiet -- node ./build/server/index.js"
```

The Dockerfile's `CMD` runs node directly and never goes through `start`, so production
is unaffected by dotenvx.

## 4. `.gitignore`

```
# Prisma generated client (regenerated on install via postinstall)
app/database/generated
```

## 5. `biome.json`

Exclude the generated client from `files.includes`:

```jsonc
"!**/app/database/generated/**/*"
```

And allow `process.env` where Prisma legitimately needs it — the base template sets
`noProcessEnv: "error"` globally:

```jsonc
"overrides": [
  {
    "includes": ["prisma/**", "prisma.config.ts"],
    "linter": { "rules": { "style": { "noProcessEnv": "off" } } }
  }
]
```

Add `"suspicious": { "noConsole": "off" }` to that same override once there is a seed.

## 6. `knip.json`

`app/database/db.server.ts` is a real root before anything imports it, or knip calls it
unused:

```jsonc
"entry": [..., "app/database/db.server.ts"],
"ignoreDependencies": [..., "@prisma/client", "pg"]
```

Do **not** add `app/database/generated/**` to `ignore` or `prisma.config.ts` to `entry` —
knip covers both already and reports them as redundant config.

## 7. `app/env.server.ts`

```ts
DATABASE_URL: z.string().min(1),
```

Only add `SESSION_SECRET` (`z.string().min(16)`) once the app actually has sessions. A
required secret nothing reads breaks `pnpm dev` and fails the deploy workflow's
`test -n` guard for no benefit.

## 8. `.env.example`

Must match `docker-compose.yml` verbatim, including the non-default host port, so that
copying it to `.env` just works:

```
DATABASE_URL="postgresql://__APP_NAME__:__APP_NAME__@localhost:__DEV_DB_PORT__/__APP_NAME__?schema=public"
```

## 9. Pick the dev host port deliberately

Run `docker ps` before choosing. A laptop working across several of these apps has one
Postgres per app, and every one of them defaulting to 5432 means only the first starts.
Record the allocation in the compose file's header comment.

## 10. systems-pro base template only — `scripts/cleanup.ts`

It removes `postinstall` from package.json. That was harmless when `postinstall` was only
`typegen`; it is not harmless once `postinstall` generates the gitignored Prisma client.
Make it drop only the `cleanup` script:

```ts
packageJson.scripts.cleanup = undefined
// `postinstall` deliberately survives cleanup: it runs `db:generate`, and the generated
// Prisma client is gitignored, so dropping it leaves every fresh clone unable to typecheck.
```

## Verify before handing over

Each of these caught something real:

```bash
pnpm run validate                                   # biome + tsc + tests + knip
docker compose up -d && pnpm run db:deploy          # local: "No migration found", exit 0
docker compose -p smoketest -f docker-compose.prod.yml build app
docker compose -p smoketest -f docker-compose.prod.yml up -d postgres
docker compose -p smoketest -f docker-compose.prod.yml run --rm -T app pnpm run db:deploy < /dev/null
docker compose -p smoketest -f docker-compose.prod.yml up -d app
docker compose -p smoketest -f docker-compose.prod.yml exec -T app \
  node -e "fetch('http://localhost:3000/').then(r => console.log(r.status))"
docker compose -p smoketest -f docker-compose.prod.yml down   # no -v
```

Use a throwaway `-p` project name: the prod compose in the app directory otherwise shares
a project with the dev `docker-compose.yml` and will recreate the dev database container
with production settings.

Also confirm the deploy workflow's `workflows: ["..."]` string matches the validation
workflow's `name:` exactly, emoji included. A mismatch is silent — deploy simply never
fires.
