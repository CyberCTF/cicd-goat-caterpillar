# Wonderland's Jenkins controller. Configured by Configuration-as-Code (casc/jenkins.yaml) with a
# Job DSL seed that creates the two caterpillar multibranch pipelines (test + prod), and one
# init-groovy hook that loads the per-player flag into the PROD folder's credential store. The flag
# is NOT here: it resolves at boot from a root-only file the entrypoint stages out of the per-player
# input Isoloom mounts at run time. Runs as root so the entrypoint/init hook can read that root-only
# mounted secret; builds execute on the controller's own executor (`agent any`), which is where the
# poisoned pipelines land.
FROM jenkins/jenkins:lts-jdk21

USER root

# git + curl for the in-controller solver/self-check (the base image already ships git for SCM).
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Plugins (resolved for this controller version).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration-as-Code + the Job DSL seed, outside JENKINS_HOME so they are read as-is at boot.
COPY casc/ /usr/share/jenkins/casc/
# init-groovy hook: loads the staged flag into the PROD folder's `flag2` credential after JCasC has
# created the folders. Placed under ref/ so jenkins.sh copies it into $JENKINS_HOME/init.groovy.d/.
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

COPY entrypoint.sh /usr/local/bin/cat-jenkins-entrypoint.sh
COPY solve.sh /usr/local/bin/cat-solve
RUN chmod 0755 /usr/local/bin/cat-jenkins-entrypoint.sh /usr/local/bin/cat-solve

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    SECRETS=/run/lab/casc_secrets \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cat-jenkins-entrypoint.sh"]
