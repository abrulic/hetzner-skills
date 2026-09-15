# Hetzner skills

Agent skills for deploying a Node/Prisma app to a single Hetzner box: cloud firewall,
Docker Compose (Caddy + app + Postgres), `prisma migrate deploy`, volumes, backups,
and GitHub deploy.

This repo is **only** that pattern. Code-quality and test skills live elsewhere.

## Skill

| Skill | When |
|---|---|
| [hetzner-app-deploy](skills/hetzner-app-deploy/SKILL.md) | Starting a new app, or `/hetzner-app-deploy` |

Templates (Dockerfile, both Composes, Caddy, Prisma, workflows, backup script,
runbook) sit next to the skill. The agent copies them into **the new app's
repository** and substitutes `__APP_NAME__`, `__HOSTNAME__`, `__ACME_EMAIL__` and
`__DEV_DB_PORT__`.

`references/app-wiring.md` is the other half: the edits to files the app already
has — Prisma deps and scripts, `pnpm-workspace.yaml`, biome, knip, the env schema.
A bare base template has no Prisma, so `pnpm run db:deploy` does not exist until
that is done, and the deploy workflow calls it.

There is no blank skeleton GitHub repo. Create the next product's repo, then run
the skill. That way it also works on an app that already exists — which is the
usual case, since deployment tends to get added after the app does.

## New laptop

```bash
git clone git@github.com:abrulic/hetzner-skills.git ~/Desktop/hetzner-skills
mkdir -p ~/.grok/skills ~/.claude/skills ~/.agents/skills
ln -sfn ~/Desktop/hetzner-skills/skills/* ~/.grok/skills/
ln -sfn ~/Desktop/hetzner-skills/skills/* ~/.claude/skills/
ln -sfn ~/Desktop/hetzner-skills/skills/* ~/.agents/skills/
```

Grok also needs this path (alongside any other skills dirs):

```toml
# ~/.grok/config.toml
[skills]
paths = ["~/Desktop/hetzner-skills/skills"]
```

## Next app

1. Create **that** app's GitHub repository.
2. In a session in that repo: `/hetzner-app-deploy`, or run the copying yourself:

   ```bash
   ~/Desktop/hetzner-skills/scripts/apply.sh --name fleet_manager \
     --hostname app.fleet.ba --email admin@fleet.ba --dev-port 5440 \
     --repo systems-pro/fleet-manager --target . --dry-run
   ```
3. Give name, hostname, Let's Encrypt email, and whether this is a new server or a
   shared box for your own apps (never two clients on one machine).
4. The skill picks a free host port for the local database — `docker ps` first, since
   every one of these apps runs its own Postgres.

## License

MIT.
