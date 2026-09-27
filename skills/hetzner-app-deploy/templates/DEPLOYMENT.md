<!-- TEMPLATE-NOTE goes in the app repo as docs/DEPLOYMENT.md; scripts/apply.sh strips this line -->
# Deployment runbook

Everything here that is *not* a one-time step is already automated in
`.github/workflows/deploy.yml`. This document is the part a human does once, by hand.

The shape of the thing: one Hetzner box runs three containers — **Caddy** (TLS, the only
thing with published ports), **app** (Node, port 3000, internal), and **Postgres** (5432,
internal). Nothing reaches Postgres from outside the machine, which is why the firewall
never opens 5432.

---

## Before you start

- [ ] A domain you control, so you can add a DNS **A record**
- [ ] The repo pushed to GitHub (`__REPO__`)
- [ ] `openssl` locally, for generating secrets

---

## Part 1 — Fill in the two placeholders

`Caddyfile` ships with `__HOSTNAME__` and `__ACME_EMAIL__` in it. Caddy will crash-loop
until both are real, which is deliberate: the alternative is silently serving plain HTTP.

| Placeholder | What it is |
|---|---|
| `__HOSTNAME__` | The public web address, e.g. `app.example.ba`. **Not** the server. This is the name people type, and the name Let's Encrypt issues a certificate for. |
| `__ACME_EMAIL__` | An address you actually read. Let's Encrypt mails certificate-expiry warnings there. It is not published. |

Commit that change before deploying.

---

## Part 2 — Hetzner console

**Server.** CX23 (2 vCPU, 4 GB RAM, 40 GB NVMe) in Falkenstein, Ubuntu 26.04 LTS. Add
your SSH public key during creation — password login gets turned off below. Around
€7.60/mo including the IPv4 and backups.

**Firewall.** Hetzner's *cloud* firewall, not `ufw` — Docker writes its own iptables rules
and punches straight through an in-VM firewall.

- Inbound: TCP **22**, **80**, **443**, plus **ICMP**
- Outbound: **leave empty** (empty means unrestricted; adding one rule silently blocks the rest)
- **Attach it to the server.** A firewall that exists but is not attached does nothing.
- Do **not** open 5432.

**Note the IPv4.** That is what the DNS A record points at. Ignore the IPv6 — no AAAA
record is published.

Add it to `~/.ssh/config` so the rest of this is short:

```
Host __APP_NAME__
  HostName <THE_IPV4>
  User root
  IdentityFile ~/.ssh/__APP_NAME__
```

---

## Part 3 — DNS

One **A record**: `__HOSTNAME__` → the IPv4 from Part 2. TTL 300 while you are setting up.

Wait for it to actually resolve before starting Caddy — Let's Encrypt validates by
connecting to that name, and repeated failures burn rate limit:

```bash
dig +short __HOSTNAME__      # must print the Hetzner IPv4
```

---

## Part 4 — Base server setup

```bash
ssh __APP_NAME__

apt update && apt upgrade -y
timedatectl set-timezone __TIMEZONE__

apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# 4 GB of RAM plus a Docker build is tight; swap keeps the build from being OOM-killed.
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

Confirm key-only SSH — `PasswordAuthentication no` in `/etc/ssh/sshd_config` (and in
anything under `/etc/ssh/sshd_config.d/`), then `systemctl restart ssh`. **Keep your
current session open** while you verify a second one still works.

Then install Docker CE and the Compose plugin from Docker's own apt repo (not Ubuntu's
`docker.io`), and `systemctl enable --now docker`.

---

## Part 5 — Give the server read access to the repo

A **deploy key**, generated on the server, read-only. Not a personal key.

```bash
ssh-keygen -t ed25519 -C "__APP_NAME__ deploy" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

GitHub → repo → Settings → Deploy keys → Add → paste → **leave "Allow write access"
unchecked**.

```bash
mkdir -p /srv
git clone git@github.com:__REPO__.git /srv/__APP_NAME__
```

The directory name matters: Compose derives the project name from it, and the volume
names (`__APP_NAME___pgdata`) follow from that.

---

## Part 6 — Secrets

```bash
cd /srv/__APP_NAME__
umask 077
printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)" > .env
chmod 600 .env
```

Hex, not base64 — this value is interpolated into a `postgresql://` URL, and base64's `+`
and `/` would corrupt it.

Copy that same password into GitHub → Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|---|---|---|
| Secret | `POSTGRES_PASSWORD` | the hex string you just generated |
| Secret | `SSH_PRIVATE_KEY` | a **private** key whose public half is in the server's `/root/.ssh/authorized_keys` |
| Variable | `SSH_HOST` | the server's IPv4 |

`SSH_PRIVATE_KEY` is for the GitHub runner logging *in* to the server; the deploy key from
Part 5 is the server logging in to *GitHub*. Two different keys, opposite directions.

Add a row here for every secret the app's env schema requires — the deploy workflow
writes them all into `.env` and fails loudly on a missing one.

---

## Part 7 — First boot

Order matters here — the app must not start against a database that has not been migrated.

```bash
cd /srv/__APP_NAME__
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d postgres
docker compose -f docker-compose.prod.yml run --rm app pnpm run db:deploy
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

With no models in `prisma/schema.prisma` yet, `db:deploy` prints *"No migration found in
prisma/migrations"* and exits 0. That is expected — it starts applying migrations the
moment you commit one.

If the app has a seed, run it **once** here, then change the seeded password.

Verify: `curl -I https://__HOSTNAME__` should return 200 over TLS. If Caddy is looping,
`docker compose -f docker-compose.prod.yml logs caddy` almost always says the A record is
missing or still points somewhere else.

---

## Part 8 — Nightly backups

Hetzner's server snapshots are a disaster-recovery tool, not a backup — they restore the
whole machine to a point in time, so you cannot pull one table back out. Take dumps too.

```bash
install -m 755 /srv/__APP_NAME__/deploy/backup.sh /usr/local/bin/__APP_NAME__-backup.sh
crontab -e
```

```cron
30 2 * * * /usr/local/bin/__APP_NAME__-backup.sh >> /var/log/__APP_NAME__-backup.log 2>&1
```

That file is appended to nightly and nothing truncates it, so give it a rotation the day
you create it — an unbounded log on a small disk is the same fault as an uncapped
container log, just slower:

```bash
cat > /etc/logrotate.d/__APP_NAME__ <<'ROTATE'
/var/log/__APP_NAME__-backup.log {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  copytruncate
}
ROTATE
logrotate --debug /etc/logrotate.d/__APP_NAME__
```

`copytruncate` because cron holds the file open across the rotation; without it the old
inode keeps being written to and the new file stays empty.

Run it once by hand and confirm a non-empty `.dump` lands in `/var/backups/__APP_NAME__/`.

**Get a copy off the box** — a backup that lives only on the machine it protects is not a
backup. `rsync` the directory elsewhere periodically.

**Test a restore once, now, before there is real data to lose:**

```bash
docker compose -f docker-compose.prod.yml exec -T postgres createdb -U __APP_NAME__ restore_test
docker compose -f docker-compose.prod.yml exec -T postgres pg_restore \
  -U __APP_NAME__ -d restore_test < /var/backups/__APP_NAME__/<file>.dump
docker compose -f docker-compose.prod.yml exec -T postgres psql -U __APP_NAME__ -d restore_test -c '\dt'
docker compose -f docker-compose.prod.yml exec -T postgres dropdb -U __APP_NAME__ restore_test
```

---

## Part 9 — Shipping changes

Nothing by hand. Merge to `main` → the validation workflow runs → on success the deploy
workflow fires and, on the server, does: `git reset --hard origin/main`, build, **dump the
database**, `db:deploy`, `up -d --force-recreate app`.

`workflow_dispatch` on the Deploy workflow re-runs the same thing without a code change —
that is how you push a rotated secret.

Two rules that keep this safe:

- **Migrations run before the new container serves.** For the seconds between, the *old*
  code is talking to the *new* schema. A migration must be backward-compatible with the
  code already running — add a nullable column and backfill in one deploy, make it
  required in the next.
- **Never `docker compose down -v`.** `-v` deletes the volumes: the database *and* the
  issued TLS certificates.

---

## Invariants

- The server holds nothing that is not in git or in a dump.
- One client per box. This machine serves this app only.
- `.env` is mode 600 and never committed.
- Hex secrets, not base64.
- Postgres is never published to the host in production.
- Seed is one-shot. Do not re-seed production.

---

## When the app grows

| When you add | Do this |
|---|---|
| Sessions / auth | `SESSION_SECRET` → the zod schema in `app/env.server.ts`, the `app.environment` block in `docker-compose.prod.yml`, the `.env` heredoc **and the required-variable loop** in the deploy workflow, and a GitHub secret. All five, every time |
| A public origin (OAuth callbacks, links in email) | An `APP_URL` the schema requires — it cannot be inferred from a request Caddy has already proxied, and a wrong one sends somebody's browser to the wrong host mid-sign-in |
| Transactional email | The provider's key, **and the From address**. Most providers ship a shared test sender that only delivers to the account holder; left unset in production every message is silently refused. Require both when `APP_ENV` is production |
| Anything whose failure is swallowed | Auth flows deliberately answer the same way whether or not an address exists, which means a broken mail provider looks exactly like a working one. Its configuration has to fail at boot, because nothing downstream will |
| File uploads | A named volume in `docker-compose.prod.yml` (uploads written into the container filesystem die with it), plus a `tar` of that volume in `deploy/backup.sh` — a database dump alone restores to broken file references |
| Seed data | `prisma/seed.ts`, a `migrations.seed` entry in `prisma.config.ts`, and `COPY` the files it imports into the runtime stage of the `Dockerfile` |
| A second app of yours | Do **not** add it here if it belongs to a different client. For your own apps, a shared Caddy on a `web` Docker network, one Postgres per app — see `references/host-setup.md` |
