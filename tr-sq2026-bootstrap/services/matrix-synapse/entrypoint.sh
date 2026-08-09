#!/bin/sh
set -eu

# /data is the Azure Files share. It holds the three pieces of state that must
# survive a revision replacement: the signing key (its loss invalidates every
# event this server ever signed), the media store, and the rendered config.
DATA_DIR="${SYNAPSE_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR/media_store"

python /usr/local/bin/render_config.py /templates/homeserver.yaml.template "$DATA_DIR/homeserver.yaml"
python /usr/local/bin/render_config.py /templates/turksquare-appservice.yaml.template "$DATA_DIR/turksquare-appservice.yaml"

if [ ! -f "$DATA_DIR/log.config" ]; then
  cat > "$DATA_DIR/log.config" <<'LOGCONFIG'
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
loggers:
  synapse.storage.SQL:
    level: WARNING
  # Access tokens and message bodies must never reach Log Analytics.
  synapse.http.server:
    level: WARNING
root:
  level: INFO
  handlers: [console]
disable_existing_loggers: false
LOGCONFIG
fi

# Creates the signing key only when it is absent; an existing key is left
# untouched. Also applies any pending database schema migration.
python -m synapse.app.homeserver --config-path "$DATA_DIR/homeserver.yaml" --generate-keys

exec python -m synapse.app.homeserver --config-path "$DATA_DIR/homeserver.yaml"
