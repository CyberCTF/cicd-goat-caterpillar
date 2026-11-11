# Wonderland's lightweight git host: Gitea, configured for the lab (installed, HTTP only, SQLite on
# the /data volume). The caterpillar repository is NOT baked into the image: its sample source is
# staged at /opt/caterpillar-src and pushed into Gitea at run time by the Isoloom setup job
# (seed.sh), which also creates the org and users. No challenge secret lives here.
# gitea/gitea:1.22, pinned to its multi-arch digest as resolved on 2026-11-11.
FROM gitea/gitea:1.22@sha256:538658de667c5d098a274f2f63aa6ec891d88f670cdd5282cf27221ba747dda4

ENV GITEA_WORK_DIR=/data \
    GITEA_ADMIN_USER=wonderland_admin \
    GITEA_ADMIN_PASS=W0nderland-admin

COPY app.ini /etc/gitea/app.ini
COPY repo-src/ /opt/caterpillar-src/
COPY entrypoint.sh /usr/local/bin/cat-gitea-entrypoint.sh
RUN chmod 0755 /usr/local/bin/cat-gitea-entrypoint.sh && chmod 0644 /etc/gitea/app.ini

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/cat-gitea-entrypoint.sh"]
