// Seed job (run by Configuration-as-Code) that creates Wonderland's two caterpillar pipelines, each
// in its own folder so that credentials can be scoped between them.
//
// Both are git-backed multibranch Pipelines over the Gitea repository, rescanned every minute (a
// periodic SCM poll — no inbound webhook; this is the version-robust alternative to the Jenkins Gitea
// plugin, see UPSTREAM.md). Whoever controls the Jenkinsfile a build runs controls what the
// controller executes — which is what both poisoned-pipeline stages abuse.
//
//   caterpillar-pr/wonderland-caterpillar-test
//     Discovers PULL-REQUEST head refs (refs/pull/*/head). Gitea publishes those refs in the BASE
//     repository for pull requests opened from FORKS too, so this pipeline builds untrusted fork code.
//     The controller-wide `gitea_token` env var is exposed to it (stage 1: the write token leaks).
//
//   caterpillar-release/wonderland-caterpillar-prod
//     Discovers BRANCHES (so it builds `main`). The per-player `flag2` credential is scoped to this
//     folder (loaded by init.groovy.d), so only this pipeline can bind it (stage 2: the flag leaks,
//     but only after the attacker uses the stolen write token to push to main).

folder('caterpillar-pr') {
    displayName('caterpillar » pull requests (untrusted)')
}
folder('caterpillar-release') {
    displayName('caterpillar » release (trusted)')
}

multibranchPipelineJob('caterpillar-pr/wonderland-caterpillar-test') {
    displayName('wonderland-caterpillar-test')
    branchSources {
        branchSource {
            source {
                git {
                    id('wonderland-caterpillar-test')
                    remote('http://gitea:3000/Wonderland/caterpillar.git')
                    credentialsId('gitea-jenkins')
                    traits {
                        // Discover pull-request head refs (refs/pull/*/head). This is a trait of the
                        // core git plugin, not the Gitea plugin, so it does not depend on a fragile
                        // Jenkins<->Gitea plugin pairing. Fork PR heads live here in the base repo.
                        //
                        // The name mapping must keep the ref's path shape (`pull/<n>/head`, not the
                        // default dash-mapped `pull-<n>`): the build resolves the head by matching its
                        // name against the fetched remote-tracking ref `origin/pull/<n>/head`, so a
                        // dash-mapped name fails to check out. Keeping the slashes makes it resolve.
                        discoverOtherRefsTrait {
                            ref('pull/*/head')
                            nameMapping('pull/@{1}/head')
                        }
                    }
                }
            }
        }
    }
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
    orphanedItemStrategy {
        discardOldItems {
            numToKeep(20)
        }
    }
    triggers {
        periodicFolderTrigger {
            interval('1m')
        }
    }
}

multibranchPipelineJob('caterpillar-release/wonderland-caterpillar-prod') {
    displayName('wonderland-caterpillar-prod')
    branchSources {
        branchSource {
            source {
                git {
                    id('wonderland-caterpillar-prod')
                    remote('http://gitea:3000/Wonderland/caterpillar.git')
                    credentialsId('gitea-jenkins')
                    traits {
                        gitBranchDiscovery()
                    }
                }
            }
        }
    }
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
    orphanedItemStrategy {
        discardOldItems {
            numToKeep(20)
        }
    }
    triggers {
        periodicFolderTrigger {
            interval('1m')
        }
    }
}
