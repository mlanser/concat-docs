# container.just — drive the project's dev container from the terminal.
#
# VENDORED from mlanser/f451labs-templates (just/). Do not edit in a project repo.
#
# Uses the same .devcontainer/ that VS Code's "Reopen in Container" uses, through
# @devcontainers/cli. Git and GitHub commands (start/commit/pr/done) stay on the host.

# Build and start the dev container
up:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -d .devcontainer ] || { echo "no .devcontainer/ here — this project runs on the host"; exit 0; }
    command -v devcontainer >/dev/null || { echo "error: devcontainer CLI missing — npm install -g @devcontainers/cli" >&2; exit 1; }
    "{{just_executable()}}" --justfile "{{justfile()}}" _engine
    devcontainer up --workspace-folder "$PWD"

# Run a recipe inside the dev container: `just in check`, `just in test -k api`
[positional-arguments]
in +args:
    #!/usr/bin/env bash
    set -euo pipefail
    # Fails rather than no-ops: `just in check` must never look green when nothing ran.
    [ -d .devcontainer ] || { echo "error: no .devcontainer/ here — run 'just $*' on the host instead" >&2; exit 1; }
    command -v devcontainer >/dev/null || { echo "error: devcontainer CLI missing — npm install -g @devcontainers/cli" >&2; exit 1; }
    "{{just_executable()}}" --justfile "{{justfile()}}" _engine
    devcontainer exec --workspace-folder "$PWD" just "$@"

# Open an interactive shell inside the dev container (not `shell`: Django repos own that name)
container-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -d .devcontainer ] || { echo "no .devcontainer/ here — this project runs on the host"; exit 0; }
    command -v devcontainer >/dev/null || { echo "error: devcontainer CLI missing — npm install -g @devcontainers/cli" >&2; exit 1; }
    "{{just_executable()}}" --justfile "{{justfile()}}" _engine
    devcontainer exec --workspace-folder "$PWD" bash -l

# Fail fast, with the fix, when the Docker engine is down (devcontainer's own error is a
# long Node stack trace). OrbStack on the Macs, docker-ce under systemd on steve.
_engine:
    #!/usr/bin/env bash
    docker info >/dev/null 2>&1 && exit 0
    if command -v orb >/dev/null; then fix="orb start"; else fix="sudo systemctl start docker"; fi
    echo "error: Docker engine is not running — start it with: $fix" >&2
    exit 1
