# concat-docs — CLI that concatenates markdown files into one output file (Python/uv,
# src/ layout, setuptools build). Run `just` to list.
#
# The git/GitHub workflow (status, start, commit, pr, done, tidy, issue, ship), `act`,
# secrets and container recipes come from the shared modules in .just/, vendored from
# mlanser/f451labs-templates. Reference: docs/HOWTO.md in that repo.

import '.just/all.just'

# List available recipes
default:
    @just --list

# Install deps and the git hooks for every stage .pre-commit-config.yaml installs (safe to re-run)
setup:
    uv sync
    prek install --hook-type pre-commit --hook-type post-checkout --hook-type post-merge --hook-type post-rewrite

# Lint + format check with the ruff version .pre-commit-config.yaml pins (CI runs this; no tests yet)
check:
    uvx ruff@0.15.5 check
    uvx ruff@0.15.5 format --check
