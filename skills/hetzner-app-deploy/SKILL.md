---
name: hetzner-app-deploy
description: >
  Scaffold Hetzner production for a Node/Prisma app: cloud firewall, Docker Compose
  (Caddy + app + Postgres), prisma migrate deploy, volumes, backups, and GitHub
  deploy. Use when starting a new app repo, asking to deploy to Hetzner, or running
  /hetzner-app-deploy. Do not use for app feature work or for this skills repo itself.
---

# Hetzner app deploy

This skill **is** the template. Copy files from `templates/` in this skill directory
into the **new app's** repository. Substitute `__APP_NAME__`, `__HOSTNAME__`, and
`__ACME_EMAIL__`. Do not invent a blank skeleton GitHub repo. Do not copy another
app's hostname, IP, or secrets.

Host setup commands: `references/host-setup.md`.

## Ask first

1. App name (filesystem-safe, used for `/srv/<name>`, DB name, backup path).
2. Public hostname.
3. Let's Encrypt email.
4. New Hetzner server, or a **your-projects** shared box (never a box that already
   serves a different client).

## What you copy

| Piece | Rule |
|---|---|
| Cloud firewall | Inbound TCP 22, 80, 443 + ICMP. **Outbound rules empty.** Attach it. **No 5432.** Hetzner cloud firewall, not ufw — Docker punches through in-VM iptables. |
| Host | timezone, 2 GiB swap, unattended-upgrades, key-only SSH |
| Docker CE + compose plugin | `references/host-setup.md` |
| GitHub deploy key | Server key, read-only, not a personal key |
| `/srv/<name>` | git clone of **this** app |
| Compose | `caddy` (80/443) + `app` (3000, internal) + `postgres` (5432, internal) |
| Prisma | `pnpm run db:deploy` → `prisma migrate deploy` after Postgres is healthy, **before** the app serves |
| Volumes | `pgdata`, upload dirs, `caddy-data` / `caddy-config`. Never `docker compose down -v` |
| Caddy | TLS, HSTS, reverse_proxy to `app:3000` |
| Nightly dump | `pg_dump -Fc` to `/var/backups/<name>/`, 14 days, test a restore once |
| GitHub | validate on PR/main; deploy only after validate succeeds; dump before migrate; `--force-recreate` app |

Files from `templates/` → the app repo:

- `Dockerfile` → `Dockerfile`
- `docker-compose.prod.yml` → `docker-compose.prod.yml`
- `Caddyfile` → `Caddyfile`
- `dockerignore` → `.dockerignore`
- `validate.yml` → `.github/workflows/validate.yml`
- `deploy.yml` → `.github/workflows/deploy.yml`
- `backup.sh` → installed on the server as `/usr/local/bin/__APP_NAME__-backup.sh`

Adapt Dockerfile `COPY` lines and compose `environment` / volumes to that app's env
schema and upload paths. Match `engines.node`. Keep the invariants.

## First boot (order is the product)

```bash
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d postgres
docker compose -f docker-compose.prod.yml run --rm app pnpm run db:deploy
docker compose -f docker-compose.prod.yml up -d
# seed once, then change that password
```

`DATABASE_URL` host is the Compose service name `postgres`, not `localhost`.

## Later deploys

Dump the live DB, then `db:deploy`, then `up -d --force-recreate app`. Migrations must
stay backward-compatible with the container still serving.

## Invariants

- The server holds nothing that is not in git or a dump.
- One **client** per box. Your own apps may share one Caddy + one Compose project per
  app (`references/host-setup.md`); Postgres stays per-app on the private network.
- Hex secrets (`openssl rand -hex`), not base64 — they go into a `postgresql://` URL.
- `.env` on the server is mode 600, not in git.
- Seed is one-shot. Do not re-seed production.
- Copy `prisma/` (and whatever seed imports) into the runtime image so `migrate deploy`
  works.

## Do not

- Create a template-only GitHub repository.
- Point at some other project's files on disk. This skill's `templates/` is the source.
- Skip firewall attach, empty outbound rules, or `db:deploy` before `up -d`.
