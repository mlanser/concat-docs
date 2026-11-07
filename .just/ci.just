# ci.just — run GitHub Actions locally with gh-act.
#
# VENDORED from mlanser/f451labs-templates (just/). Do not edit in a project repo.
#
# Good for iterating on workflow YAML before pushing. NOT proof a PR will pass: act
# cannot evaluate rulesets or required contexts, and does not run macOS jobs.
# Needs gh-act (`ds bootstrap-extra`) and a Docker runtime (OrbStack / docker-ce).

# Run CI jobs locally: `just act` (all PR jobs), `just act test`, `just act test push`
act $job="" $event="pull_request":
    #!/usr/bin/env bash
    set -euo pipefail
    [ -d .github/workflows ] || { echo "no .github/workflows here — nothing to run"; exit 0; }
    gh extension list | grep -q 'nektos/gh-act' || { echo "error: gh-act is not installed — run: ds bootstrap-extra" >&2; exit 1; }
    "{{just_executable()}}" --justfile "{{justfile()}}" _engine   # defined in container.just
    # act ignores `docker context` and dials /var/run/docker.sock, which can point at a
    # different (or removed) engine than the one docker uses. Follow the active context.
    if [ -z "${DOCKER_HOST:-}" ]; then
        DOCKER_HOST="$(docker context inspect --format '{{{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
        [ -z "$DOCKER_HOST" ] || export DOCKER_HOST
    fi
    # --pull=false: use the local runner image (still pulled when missing) instead of
    # re-downloading several GB on every run.
    args=("$event" --pull=false -P ubuntu-latest=catthehacker/ubuntu:act-latest)
    [ -z "$job" ] || args+=(-j "$job")
    [ "$(uname -s)-$(uname -m)" != Darwin-arm64 ] || args+=(--container-architecture linux/amd64)
    # Secrets are passed by NAME (-s NAME); act reads the values from the environment,
    # so no secret value ever appears in argv or on disk.
    GITHUB_TOKEN="$(gh auth token)"
    export GITHUB_TOKEN
    args+=(-s GITHUB_TOKEN)
    if [ -f .env.refs ]; then
        for name in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env.refs | cut -d= -f1); do args+=(-s "$name"); done
        exec pass-cli run --env-file .env.refs -- gh act "${args[@]}"
    fi
    exec gh act "${args[@]}"
