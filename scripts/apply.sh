#!/usr/bin/env bash
# Copy the hetzner-app-deploy templates into an app repo and substitute the placeholders.
#
# This is the mechanical half only. The judgement half — adapting the Dockerfile COPY set,
# deciding which secrets the app actually reads, wiring Prisma into package.json, biome and
# knip — is in references/app-wiring.md, and the checklist at the end points back to it.
#
# Never overwrites. Existing files are reported and skipped unless --force.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/hetzner-app-deploy" && pwd)"
TEMPLATES="$SKILL_DIR/templates"

NAME="" HOSTNAME_ARG="" EMAIL="" DEV_PORT="" REPO="" TIMEZONE="Europe/Sarajevo"
TARGET="." FORCE=0 DRY_RUN=0

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
	cat <<'USAGE'
usage: apply.sh --name <app_name> --hostname <fqdn> --email <acme-email>
                --dev-port <port> --repo <owner/name>
                [--timezone <tz>] [--target <dir>] [--force] [--dry-run]

  --name      filesystem- and Postgres-safe: lowercase, digits, underscores.
              Becomes /srv/<name>, the DB user/database, and the backup path.
  --hostname  public web address, e.g. app.example.ba. Not the server.
  --email     Let's Encrypt expiry warnings go here. Ask the user; never guess.
  --dev-port  HOST port for the local database. Run `docker ps` first — every app
              of yours runs its own Postgres and they cannot all have 5432.
  --repo      owner/name on GitHub, used by the runbook's clone step.
  --target    app repo root (default: current directory)
  --force     overwrite existing files instead of skipping them
  --dry-run   print what would happen, write nothing
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		--name) NAME="${2:-}"; shift 2 ;;
		--hostname) HOSTNAME_ARG="${2:-}"; shift 2 ;;
		--email) EMAIL="${2:-}"; shift 2 ;;
		--dev-port) DEV_PORT="${2:-}"; shift 2 ;;
		--repo) REPO="${2:-}"; shift 2 ;;
		--timezone) TIMEZONE="${2:-}"; shift 2 ;;
		--target) TARGET="${2:-}"; shift 2 ;;
		--force) FORCE=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
done

[ -n "$NAME" ] && [ -n "$HOSTNAME_ARG" ] && [ -n "$EMAIL" ] && [ -n "$DEV_PORT" ] && [ -n "$REPO" ] || {
	usage >&2; die "missing required argument"
}

# An app name with a hyphen needs quoting in psql and makes pg_dump -U awkward; one
# starting with a digit is not a valid unquoted Postgres identifier at all.
[[ "$NAME" =~ ^[a-z][a-z0-9_]*$ ]] || die "--name must match ^[a-z][a-z0-9_]*$ (got '$NAME')"
# The final label must be alphabetic: an IP address here would pass a naive FQDN regex,
# and Let's Encrypt does not issue certificates for bare IPs — Caddy would crash-loop.
[[ "$HOSTNAME_ARG" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$ ]] \
	|| die "--hostname must be a domain name with an alphabetic TLD, not an IP (got '$HOSTNAME_ARG')"
[[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "--email is not an address (got '$EMAIL')"
[[ "$DEV_PORT" =~ ^[0-9]+$ ]] && [ "$DEV_PORT" -ge 1024 ] && [ "$DEV_PORT" -le 65535 ] \
	|| die "--dev-port must be 1024-65535 (got '$DEV_PORT')"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "--repo must be owner/name (got '$REPO')"

[ -d "$TEMPLATES" ] || die "templates not found at $TEMPLATES"
[ -d "$TARGET" ] || die "--target is not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ -d "$TARGET/.git" ] || warn "$TARGET is not a git repository — the deploy workflow clones from GitHub"

# Best-effort: a port already bound means the dev database silently fails to start later.
if command -v docker >/dev/null 2>&1; then
	if docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE "(^|[^0-9])${DEV_PORT}->"; then
		die "host port $DEV_PORT is already published by a running container — pick another"
	fi
fi

echo
echo "  app        $NAME"
echo "  hostname   $HOSTNAME_ARG"
echo "  dev port   $DEV_PORT"
echo "  target     $TARGET"
[ "$DRY_RUN" -eq 1 ] && echo "  mode       DRY RUN — nothing is written"
echo

# template:destination
MAPPING=(
	"Dockerfile:Dockerfile"
	"dockerignore:.dockerignore"
	"docker-compose.dev.yml:docker-compose.yml"
	"docker-compose.prod.yml:docker-compose.prod.yml"
	"Caddyfile:Caddyfile"
	"schema.prisma:prisma/schema.prisma"
	"prisma.config.ts:prisma.config.ts"
	"db.server.ts:app/database/db.server.ts"
	"deploy.yml:.github/workflows/deploy.yml"
	"validate.yml:.github/workflows/validate.yml"
	"backup.sh:deploy/backup.sh"
	"DEPLOYMENT.md:docs/DEPLOYMENT.md"
)

written=0 skipped=0
for pair in "${MAPPING[@]}"; do
	src="$TEMPLATES/${pair%%:*}"
	dest="$TARGET/${pair##*:}"
	rel="${pair##*:}"

	[ -f "$src" ] || die "missing template: $src"

	if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
		info "skip    $rel (exists)"
		skipped=$((skipped + 1))
		continue
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		info "would   $rel"
		written=$((written + 1))
		continue
	fi

	mkdir -p "$(dirname "$dest")"
	sed -e '/TEMPLATE-NOTE-START/,/TEMPLATE-NOTE-END/d' "$src" \
		| grep -v 'TEMPLATE-NOTE' \
		| sed -e "s|__APP_NAME__|$NAME|g" \
		      -e "s|__HOSTNAME__|$HOSTNAME_ARG|g" \
		      -e "s|__ACME_EMAIL__|$EMAIL|g" \
		      -e "s|__DEV_DB_PORT__|$DEV_PORT|g" \
		      -e "s|__REPO__|$REPO|g" \
		      -e "s|__TIMEZONE__|$TIMEZONE|g" \
		> "$dest"
	[ "$rel" = "deploy/backup.sh" ] && chmod +x "$dest"
	info "write   $rel"
	written=$((written + 1))
done

echo
echo "  $written written, $skipped skipped"
echo

# The deploy workflow triggers off the validation workflow's *name*. If the app already
# had one, the name almost certainly differs and the mismatch is completely silent.
VALIDATE="$TARGET/.github/workflows/validate.yml"
DEPLOY="$TARGET/.github/workflows/deploy.yml"
if [ "$DRY_RUN" -eq 0 ] && [ -f "$VALIDATE" ] && [ -f "$DEPLOY" ]; then
	have="$(grep -m1 '^name:' "$VALIDATE" | sed 's/^name:[[:space:]]*//')"
	want="$(grep -m1 'workflows:' "$DEPLOY" | sed -E 's/.*\["(.*)"\].*/\1/')"
	if [ "$have" = "$want" ]; then
		printf '  \033[32m✓\033[0m deploy triggers on "%s"\n\n' "$have"
	else
		printf '  \033[31m✗\033[0m TRIGGER MISMATCH — deploy would never fire\n'
		printf '      validate.yml is named : %s\n' "$have"
		printf '      deploy.yml waits for  : %s\n' "$want"
		printf '      Fix deploy.yml to match, emoji included.\n\n'
	fi
fi

cat <<NEXT
  Still to do by hand — see references/app-wiring.md:

    1.  pnpm add @prisma/adapter-pg@7.9.1 @prisma/client@7.9.1 pg@8.23.0
        pnpm add -D prisma@7.9.1
    2.  pnpm-workspace.yaml  allowBuilds: @prisma/client, @prisma/engines, prisma
    3.  package.json         db:generate/migrate/deploy/reset/studio,
                             postinstall runs db:generate, dotenvx on dev + start
    4.  .gitignore           app/database/generated
    5.  biome.json           exclude the generated client; noProcessEnv off for prisma/
    6.  knip.json            entry app/database/db.server.ts;
                             ignoreDependencies @prisma/client, pg
    7.  app/env.server.ts    DATABASE_URL: z.string().min(1)
    8.  .env.example         DATABASE_URL on port $DEV_PORT, matching docker-compose.yml
    9.  Dockerfile           adapt the COPY set if a seed imports app source
   10.  Caddyfile            nothing — already substituted. Confirm DNS first:
                             dig +short $HOSTNAME_ARG
   11.  If the app has no sessions yet, DELETE SESSION_SECRET from
        docker-compose.prod.yml and .github/workflows/deploy.yml. The workflow
        guards it with "test -n" and will fail every deploy until it is set.
        Same for the uploads volume if nothing writes uploads.

  Then verify, don't assume:

    pnpm run validate
    docker compose up -d && pnpm run db:deploy
    docker compose -p smoketest -f docker-compose.prod.yml build app
    docker compose -p smoketest -f docker-compose.prod.yml up -d postgres
    docker compose -p smoketest -f docker-compose.prod.yml run --rm -T app pnpm run db:deploy < /dev/null
    docker compose -p smoketest -f docker-compose.prod.yml up -d app
    docker compose -p smoketest -f docker-compose.prod.yml exec -T app \\
      node -e "fetch('http://localhost:3000/').then(r => console.log(r.status))"
    docker compose -p smoketest -f docker-compose.prod.yml down

NEXT
