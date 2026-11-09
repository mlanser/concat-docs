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
    # re-downloading several GB on every run. Gate jobs run on `[self-hosted, f451]`
    # (steve), deploy jobs on ubuntu-latest: both get the same image.
    img=catthehacker/ubuntu:act-latest
    args=("$event" --pull=false -P "ubuntu-latest=$img" -P "self-hosted=$img")
    [ -z "$job" ] || args+=(-j "$job")
    [ "$(uname -s)-$(uname -m)" != Darwin-arm64 ] || args+=(--container-architecture linux/amd64)
    # Secrets are passed by NAME (-s NAME); act reads the values from the environment,
    # so no secret value ever appears in argv or on disk.
    GITHUB_TOKEN="$(gh auth token)"
    export GITHUB_TOKEN
    args+=(-s GITHUB_TOKEN)
    run=(gh act)
    if [ -f .env.refs ]; then
        for name in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env.refs | cut -d= -f1); do args+=(-s "$name"); done
        run=(pass-cli run --env-file .env.refs -- gh act)
    fi
    # act skips a job whose runs-on label has no -P image and still exits 0 — a green
    # run that ran nothing. Watch the output for that and fail instead.
    set +e
    "${run[@]}" "${args[@]}" 2>&1 \
        | awk '{ print; fflush() } /Skipping unsupported platform/ { s = 1 } END { exit s ? 3 : 0 }'
    status=("${PIPESTATUS[@]}")
    set -e
    if [ "${status[1]}" = 3 ]; then
        echo "error: act skipped a job: no -P image for its runs-on labels" >&2
        exit 1
    fi
    exit "${status[0]}"
