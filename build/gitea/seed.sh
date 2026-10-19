#!/bin/sh
# Isoloom `setup` step for the Gitea machine (runs once, after Gitea is healthy, in the Gitea image,
# sharing its network namespace so Gitea is reachable at 127.0.0.1:3000). It provisions Wonderland's
# PUBLIC caterpillar repository over the Gitea API and pushes the baked sample project:
#   - org `Wonderland`, a PUBLIC repo `caterpillar`
#   - `cheshire` (the attacker): a plain account, NO collaborator access to the repo. Because the repo
#      is public, cheshire can still fork it and open a pull request — that is the whole point of
#      PUBLIC / fork-based PPE.
#   - `hatter`   (the CI robot): WRITE access. Its push credential is the `gitea_token` that Jenkins
#      wrongly exposes to every build; leaking it is the privilege escalation.
#   - `jenkins`  (the poller): READ access, used by Jenkins to poll the repositories.
# No challenge secret is handled here; the flag is a Jenkins credential injected elsewhere. The write
# robot's password is a FIXED lab value (it must match the gitea_token Jenkins exposes), not a flag.
set -eu

BASE="${GITEA_BASE_URL:-http://127.0.0.1:3000}"
ADMIN_USER="${GITEA_ADMIN_USER:-wonderland_admin}"
ADMIN_PASS="${GITEA_ADMIN_PASS:-W0nderland-admin}"
ORG="Wonderland"
REPO="caterpillar"
SRC="${CAT_SRC:-/opt/caterpillar-src}"

ATTACKER_USER="cheshire"
ATTACKER_PASS="cheshire"
ROBOT_USER="hatter"
ROBOT_PASS="TeaParty-3PE-pw"   # must match the gitea_token value baked into Jenkins' JCasC
CI_USER="jenkins"
CI_PASS="jenkins"

AUTH="$ADMIN_USER:$ADMIN_PASS"
API="$BASE/api/v1"

log() { echo "seed: $1"; }

# POST/PUT JSON as admin; tolerate 'already exists' (409/422) so the job is idempotent on restart.
api() {  # method path json
  if [ -n "${3:-}" ]; then
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" \
           -H 'Content-Type: application/json' -u "$AUTH" \
           --data "$3" "$API$2" 2>/dev/null || echo 000)
  else
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" -u "$AUTH" "$API$2" 2>/dev/null || echo 000)
  fi
  case "$code" in
    2*) return 0 ;;
    409|422) log "exists ($code): $1 $2"; return 0 ;;
    *) log "WARN $code: $1 $2 -> $(tr -d '\n' < /tmp/seed.out | cut -c1-200)"; return 1 ;;
  esac
}

# 1. Wait for the Gitea API.
i=0
while :; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "$API/version" 2>/dev/null || echo 000)
  [ "$c" = "200" ] && break
  i=$((i+1)); [ "$i" -lt 120 ] || { log "FATAL: Gitea API never answered"; exit 1; }
  sleep 2
done
log "Gitea API is up"

# 2. Idempotency: if the repo already has a main branch, everything below is already done.
c=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "$API/repos/$ORG/$REPO/branches/main" 2>/dev/null || echo 000)
if [ "$c" = "200" ]; then
  log "caterpillar already seeded; nothing to do"
  exit 0
fi

# 3. Org, users, PUBLIC repository.
api POST "/orgs" "{\"username\":\"$ORG\",\"visibility\":\"public\"}"
api POST "/admin/users" "{\"username\":\"$ATTACKER_USER\",\"email\":\"cheshire@wonderland.example\",\"password\":\"$ATTACKER_PASS\",\"must_change_password\":false}"
api POST "/admin/users" "{\"username\":\"$ROBOT_USER\",\"email\":\"hatter@wonderland.example\",\"password\":\"$ROBOT_PASS\",\"must_change_password\":false}"
api POST "/admin/users" "{\"username\":\"$CI_USER\",\"email\":\"jenkins@wonderland.example\",\"password\":\"$CI_PASS\",\"must_change_password\":false}"
api POST "/orgs/$ORG/repos" "{\"name\":\"$REPO\",\"private\":false,\"auto_init\":false,\"default_branch\":\"main\"}"

# 4. Access: hatter writes (the CI robot whose token leaks), jenkins reads (the pipeline poller).
#    cheshire (the attacker) gets NO collaborator access — only public read, enough to fork + PR.
api PUT "/repos/$ORG/$REPO/collaborators/$ROBOT_USER" "{\"permission\":\"write\"}"
api PUT "/repos/$ORG/$REPO/collaborators/$CI_USER" "{\"permission\":\"read\"}"

# 5. Push the baked sample project (the real Jenkinsfile lives here) to main.
WORK="$(mktemp -d)"
cp -a "$SRC/." "$WORK/"
cd "$WORK"
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="Wonderland Admin" GIT_AUTHOR_EMAIL="admin@wonderland.example"
export GIT_COMMITTER_NAME="Wonderland Admin" GIT_COMMITTER_EMAIL="admin@wonderland.example"
export GIT_AUTHOR_DATE="2024-03-01T09:00:00" GIT_COMMITTER_DATE="2024-03-01T09:00:00"
git -c init.defaultBranch=main init -q
git add -A
git commit -q -m "Initial import of the caterpillar package and CI pipeline"
PUSH_URL="http://$ADMIN_USER:$ADMIN_PASS@127.0.0.1:3000/$ORG/$REPO.git"
git push -q "$PUSH_URL" main
cd /
rm -rf "$WORK"

log "caterpillar seeded: public repo with main + Jenkinsfile, hatter=write, jenkins=read, cheshire=plain (fork-only)"
