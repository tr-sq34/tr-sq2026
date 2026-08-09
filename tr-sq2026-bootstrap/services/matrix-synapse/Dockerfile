# Synapse is used unmodified; this image only adds the startup step that renders
# the two templates in this directory from environment variables and generates
# the signing key on first boot.
#
# The tag is pinned deliberately. Synapse database schema upgrades are one-way:
# once a newer version has started against the database, an older version
# refuses to run. Bump this in its own commit, never as a side effect of a
# rebuild.
ARG SYNAPSE_VERSION=v1.121.1
FROM ghcr.io/element-hq/synapse:${SYNAPSE_VERSION}

COPY homeserver.yaml.template /templates/homeserver.yaml.template
COPY turksquare-appservice.yaml.template /templates/turksquare-appservice.yaml.template
COPY render_config.py /usr/local/bin/render_config.py
COPY entrypoint.sh /usr/local/bin/turksquare-entrypoint.sh

# Azure Files is mounted over SMB and does not support chown, so the container
# cannot drop to the image's `synapse` user and still write /data.
USER root
RUN chmod +x /usr/local/bin/turksquare-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/turksquare-entrypoint.sh"]
