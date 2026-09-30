default:
    @just --list

lint:
    pre-commit run --all-files

test-feature feature:
    devcontainer features test --project-folder . --features '{{feature}}' --base-image ubuntu:latest

test-global:
    devcontainer features test --project-folder . --global-scenarios-only

test:
    just test-feature opencode
    just test-feature chezmoi
    just test-global
