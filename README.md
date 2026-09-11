# Hetzner skills

Agent skills for deploying a Node/Prisma app to a single Hetzner box: cloud firewall,
Docker Compose (Caddy + app + Postgres), `prisma migrate deploy`, volumes, backups,
and GitHub deploy.

This repo is **only** that pattern. Code-quality and test skills live elsewhere.

## Skill

| Skill | When |
|---|---|
| [hetzner-app-deploy](skills/hetzner-app-deploy/SKILL.md) | Starting a new app, or `/hetzner-app-deploy` |

Templates (Dockerfile, Compose, Caddy, workflows, backup script) sit next to the
skill. The agent copies them into **the new app's repository** and substitutes
`__APP_NAME__`, `__HOSTNAME__`, `__ACME_EMAIL__`.

There is no blank skeleton GitHub repo. Create the next product's repo, then run
the skill.

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
2. In a session in that repo: `/hetzner-app-deploy`
3. Give name, hostname, Let's Encrypt email, and whether this is a new server or a
   shared box for your own apps (never two clients on one machine).

## License

MIT.
