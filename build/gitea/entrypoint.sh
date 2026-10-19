#!/bin/bash
# Wonderland Gitea entrypoint. Runs as root, prepares the data volume, creates the lab's admin user
# once (offline, before the server starts, so there is no SQLite contention), then runs `gitea web`
# as the git user. The repository, org and other users are provisioned afterwards over the API by
# the Isoloom setup job (seed.sh); nothing here holds the challenge flag.
set -eu

APP_INI=/etc/gitea/app.ini
export GITEA_WORK_DIR=/data

ADMIN_USER="${GITEA_ADMIN_USER:-wonderland_admin}"
ADMIN_PASS="${GITEA_ADMIN_PASS:-W0nderland-admin}"

mkdir -p /data/gitea/log /data/git/repositories /data/git/lfs
chown -R git:git /data
# Gitea persists auto-generated secrets (e.g. the OAuth2 JWT secret) back into the config file on
# first boot, so the config directory must be writable by the git user it runs as.
chown -R git:git /etc/gitea

if [ ! -f /data/gitea/.cat-init ]; then
  echo "gitea-entrypoint: initializing database schema"
  su-exec git gitea migrate -c "$APP_INI"
  echo "gitea-entrypoint: creating lab admin user '$ADMIN_USER'"
  su-exec git gitea admin user create \
    --username "$ADMIN_USER" --password "$ADMIN_PASS" \
    --email admin@wonderland.example --admin --must-change-password=false \
    -c "$APP_INI" || echo "gitea-entrypoint: admin user already present"
  su-exec git touch /data/gitea/.cat-init
fi

echo "gitea-entrypoint: starting gitea web"
exec su-exec git gitea web -c "$APP_INI"
