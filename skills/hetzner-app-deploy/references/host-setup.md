# Host setup

Run on the server unless noted. Substitute `__APP_NAME__`.

## Firewall (Hetzner console, not ufw)

Inbound: TCP 22, 80, 443, plus ICMP. Outbound: **empty**. Attach the firewall to the
server. Do not open 5432.

## Base box

```bash
apt update && apt upgrade -y
timedatectl set-timezone Europe/Sarajevo
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

Key-only SSH. No password login.

## Docker

Install Docker CE and the compose plugin from Docker's repo. Enable the service.

## App checkout

Deploy key on the server (read-only). Clone into `/srv/__APP_NAME__`. `.env` mode 600,
not in git. Hex secrets (`openssl rand -hex`).

## Nightly dump

Install `templates/backup.sh` as `/usr/local/bin/__APP_NAME__-backup.sh`. Cron:

```cron
30 2 * * * /usr/local/bin/__APP_NAME__-backup.sh >> /var/log/__APP_NAME__-backup.log 2>&1
```

Pull a copy off the box periodically (`rsync`). Test a restore once (`createdb
restore_test`, `pg_restore`, `\dt`, `dropdb`).

## Shared box (your apps only)

Never two different clients on one machine.

Once per server:

```bash
docker network create web
mkdir -p /srv/caddy
```

Shared Caddy on `web` (ports 80/443). Each app Compose drops its own `caddy` service,
puts `app` on `web` + `default`, keeps `postgres` on `default` only. One Postgres per
app. Add a Caddyfile block per hostname, restart Caddy.
