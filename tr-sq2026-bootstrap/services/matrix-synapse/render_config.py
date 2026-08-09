"""Renders a ${VAR} template from the environment.

Deliberately not `envsubst`: gettext-base is not in the Synapse image, and an
unset variable must be a hard failure. envsubst silently substitutes an empty
string, which would produce a syntactically valid homeserver.yaml with an empty
database password and a Synapse that fails much later with a confusing error.
"""

import json
import os
import re
import sys

PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def render(template: str) -> str:
    missing = sorted({name for name in PATTERN.findall(template) if not os.environ.get(name)})
    if missing:
        raise SystemExit(f"Missing required environment variables: {', '.join(missing)}")
    # Quoted, not pasted in raw. Every placeholder in these templates is a
    # string scalar and several of them are generated secrets, so sooner or
    # later one starts with a character YAML reads as syntax - a leading '@'
    # already took Synapse down once. A JSON string is a valid YAML flow
    # scalar and json.dumps handles the quoting and escaping.
    return PATTERN.sub(lambda match: json.dumps(os.environ[match.group(1)]), template)


def main() -> None:
    source, destination = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as handle:
        rendered = render(handle.read())
    # 0600: the rendered file holds the database password and both application
    # service tokens, and it lives on a shared volume.
    file_descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(file_descriptor, "w", encoding="utf-8") as handle:
        handle.write(rendered)


if __name__ == "__main__":
    main()
