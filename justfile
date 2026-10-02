default:
    @just --list

# Run pre-commit checks and linters across all files
lint:
    pre-commit run --all-files

# Run all Feature tests and global scenarios in a single unified run
test base_image="ubuntu:latest" *args:
    devcontainer features test --project-folder . --base-image '{{base_image}}' {{args}}

# Test a specific Feature's defaults and scenarios
test-feature feature base_image="ubuntu:latest" *args:
    devcontainer features test --project-folder . --features '{{feature}}' --base-image '{{base_image}}' {{args}}

# Run only global scenarios
test-global *args:
    devcontainer features test --project-folder . --global-scenarios-only {{args}}
