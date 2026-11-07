# secrets.just — Proton Pass (dev runtime), GitHub secrets (CI), SOPS (secrets in the repo).
#
# VENDORED from mlanser/f451labs-templates (just/). Do not edit in a project repo.
#
# .env.refs           committed; pass://<vault>/<item>/<field> pointers only, never values
# .github/secrets.txt committed; names of the GitHub secrets CI needs, never values
# *.enc.*             SOPS-encrypted files, recipients in .sops.yaml

# Run a command with the secrets from .env.refs in its environment: `just secrets-run just dev`
[positional-arguments]
secrets-run +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f .env.refs ] || { echo "error: no .env.refs here — add pass:// pointers first" >&2; exit 1; }
    exec pass-cli run --env-file .env.refs -- "$@"

# Copy one secret from Proton Pass into this repo's GitHub secrets: `just secrets-push API_KEY`
secrets-push $name:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f .env.refs ] || { echo "error: no .env.refs here" >&2; exit 1; }
    ref="$(grep -E "^${name}=" .env.refs | head -1 | cut -d= -f2- | tr -d '"' || true)"
    [ -n "$ref" ] || { echo "error: $name is not in .env.refs" >&2; exit 1; }
    # The value only ever exists in the pass-cli child and the pipe into gh.
    pass-cli run --env-file <(printf 'VAL=%s\n' "$ref") -- sh -c 'printf "%s" "$VAL"' | gh secret set "$name"
    echo "pushed $name → GitHub secrets"

# Fail if a name listed in .github/secrets.txt is missing from this repo's GitHub secrets
secrets-check:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f .github/secrets.txt ] || { echo "no .github/secrets.txt — nothing to check"; exit 0; }
    have="$(gh secret list --json name -q '.[].name')"
    missing=0
    while IFS= read -r line || [ -n "$line" ]; do
        n="$(printf '%s' "${line%%#*}" | tr -d '[:space:]')"
        [ -n "$n" ] || continue
        printf '%s\n' "$have" | grep -qxF "$n" || { echo "missing: $n"; missing=1; }
    done < .github/secrets.txt
    [ "$missing" = 0 ] && echo "all GitHub secrets present"
    exit "$missing"

# Edit a SOPS-encrypted file in place: `just sops-edit secrets/app.env.enc`
sops-edit $file:
    sops "$file"
