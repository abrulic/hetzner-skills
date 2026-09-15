---
name: hetzner-app-deploy
description: >
  Scaffold local Postgres and Hetzner production for a Node/Prisma app: cloud firewall,
  Docker Compose (Caddy + app + Postgres), Prisma wiring, prisma migrate deploy, volumes,
  backups, and GitHub deploy. Use when starting a new app repo, adding deployment or a
  local database to an existing one, asking to deploy to Hetzner, or running
  /hetzner-app-deploy. Do not use for app feature work or for this skills repo itself.
---

# Hetzner app deploy

This skill **is** the template. Copy files from `templates/` in this skill directory into
the **new app's** repository and substitute the placeholders. Do not invent a blank
skeleton GitHub repo. Do not copy another app's hostname, IP, or secrets.

Two halves, and the second is the one that gets skipped:

- **Whole-file copies** — `templates/`, listed below.
- **Edits to files the app already has** — `references/app-wiring.md`. A bare
  systems-pro base template has **no Prisma at all**, so `pnpm run db:deploy` does not
  exist until that is done, and the deploy workflow calls it.

Host setup commands: `references/host-setup.md`.

## Ask first

1. App name (filesystem-safe, used for `/srv/<name>`, DB name, backup path).
2. Public hostname. If the user does not know what that means: it is the web address
   people type, not the server — a DNS A record points it at the box's IPv4.
3. Let's Encrypt email. Ask; never fill in an address you happen to know.
4. New Hetzner server, or a **your-projects** shared box (never a box that already
   serves a different client).

Then, before writing the dev compose, run `docker ps` and pick a free host port for the
local database. Do not assume 5432.

## Placeholders

| | |
|---|---|
| `__APP_NAME__` | `/srv/<name>`, Postgres user/db, volume prefix, backup path |
| `__HOSTNAME__` | public web address |
| `__ACME_EMAIL__` | Let's Encrypt expiry warnings |
| `__DEV_DB_PORT__` | host port for the **local** database only |
| `__REPO__`, `__TIMEZONE__` | runbook only |

## What you set up

| Piece | Rule |
|---|---|
| Cloud firewall | Inbound TCP 22, 80, 443 + ICMP. **Outbound rules empty.** Attach it. **No 5432.** Hetzner cloud firewall, not ufw — Docker punches through in-VM iptables. |
| Host | timezone, 2 GiB swap, unattended-upgrades, key-only SSH |
| Docker CE + compose plugin | `references/host-setup.md` |
| GitHub deploy key | Server key, read-only, not a personal key |
| `/srv/<name>` | git clone of **this** app |
| Local Postgres | Own `docker-compose.yml`, published on a port you checked is free |
| Prisma | Deps, scripts, config, client module, lint/knip wiring — `references/app-wiring.md` |
| Prod compose | `caddy` (80/443) + `app` (3000, internal) + `postgres` (5432, internal, never published) |
| Migrate | `pnpm run db:deploy` → `prisma migrate deploy` after Postgres is healthy, **before** the app serves |
| Volumes | `pgdata`, upload dirs, `caddy-data` / `caddy-config`. Never `docker compose down -v` |
| Caddy | TLS, HSTS, reverse_proxy to `app:3000` |
| Nightly dump | `pg_dump -Fc` to `/var/backups/<name>/`, 14 days, test a restore once |
| GitHub | validate on PR/main; deploy only after validate succeeds; dump before migrate; `--force-recreate` app |

Do the copying with the script rather than by hand — 55 substitutions of `__APP_NAME__`
alone is not agent work:

```bash
<this repo>/scripts/apply.sh --name <app_name> --hostname <fqdn> --email <acme-email> \
  --dev-port <free port> --repo <owner/name> --target <app repo> [--dry-run]
```

It refuses to overwrite, validates every argument (a hyphenated app name, an IP passed as
a hostname, a port a container already holds), strips template-only notes, checks that
`deploy.yml`'s trigger matches the validation workflow's `name:`, and prints the
`app-wiring.md` checklist it cannot do itself. Then work that checklist.

Files it places:

- `Dockerfile` → `Dockerfile`
- `dockerignore` → `.dockerignore`
- `docker-compose.dev.yml` → `docker-compose.yml`
- `docker-compose.prod.yml` → `docker-compose.prod.yml`
- `Caddyfile` → `Caddyfile`
- `schema.prisma` → `prisma/schema.prisma`
- `prisma.config.ts` → `prisma.config.ts`
- `db.server.ts` → `app/database/db.server.ts`
- `validate.yml` → `.github/workflows/validate.yml` (skip if the app already validates)
- `deploy.yml` → `.github/workflows/deploy.yml`
- `backup.sh` → `deploy/backup.sh`, installed on the server as `/usr/local/bin/__APP_NAME__-backup.sh`
- `DEPLOYMENT.md` → `docs/DEPLOYMENT.md`

The templates carry `SESSION_SECRET` and an uploads volume because most of these apps
grow both. **If this one has neither yet, delete them** from `docker-compose.prod.yml`
and `deploy.yml` — the workflow guards the secret with `test -n` and will fail every
deploy until it is set.

Adapt Dockerfile `COPY` lines and compose `environment` / volumes to that app's env schema
and upload paths. Match `engines.node`. Keep the invariants.

**If the app already has a validation workflow, keep it** and make `deploy.yml`'s
`workflows: ["..."]` match its `name:` exactly, emoji included. A mismatch is silent:
deploy simply never fires.

## Local development

```bash
cp .env.example .env
docker compose up -d
pnpm run db:migrate
```

`.env.example` must match `docker-compose.yml` verbatim, host port included, so copying it
is enough.

## First boot (order is the product)

```bash
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d postgres
docker compose -f docker-compose.prod.yml run --rm app pnpm run db:deploy
docker compose -f docker-compose.prod.yml up -d
# seed once, then change that password
```

`DATABASE_URL` host is the Compose service name `postgres`, not `localhost`.

On an empty schema `migrate deploy` prints "No migration found in prisma/migrations" and
exits 0 — verified. A first deploy before any model exists is safe.

## Later deploys

Dump the live DB, then `db:deploy`, then `up -d --force-recreate app`. Migrations must stay
backward-compatible with the container still serving.

## Verify before handing over

Do not report this done on files alone. The commands are in
`references/app-wiring.md` — `pnpm run validate`, then build the production image, run
`db:deploy` inside it, start it, and fetch `/`. Use a throwaway `-p` project name for the
smoke test, and tear it down without `-v`.

## Invariants

- The server holds nothing that is not in git or a dump — `backup.sh` included.
- One **client** per box. Your own apps may share one Caddy + one Compose project per app
  (`references/host-setup.md`); Postgres stays per-app on the private network.
- Hex secrets (`openssl rand -hex`), not base64 — they go into a `postgresql://` URL.
- `.env` on the server is mode 600, not in git.
- Seed is one-shot. Do not re-seed production.
- Copy `prisma/` (and whatever seed imports) into the runtime image so `migrate deploy`
  works.
- Production Postgres has no `ports:` entry. Ever.

## Do not

- Create a template-only GitHub repository.
- Point at some other project's files on disk. This skill's `templates/` is the source.
- Skip firewall attach, empty outbound rules, or `db:deploy` before `up -d`.
- Default the local DB to host port 5432 without checking, or reuse another app's port.
- Add `SESSION_SECRET` (or any secret) to the env schema and workflow before the app
  actually reads it — the workflow's `test -n` guard then fails every deploy for nothing.
- Guess the Let's Encrypt email, or quietly fill in the hostname.
