
# Docker (Docker-in-Docker) with NVIDIA GPU support (docker-in-docker-nvidia)

Installs the NVIDIA Container Toolkit and Docker-in-Docker, enabling GPU-accelerated containers inside your development container.

## Example Usage

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/docker-in-docker-nvidia:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Select or enter an NVIDIA Container Toolkit version (e.g. 'latest' or '1.20.1'). | string | latest |
| configureDocker | Register the nvidia runtime in /etc/docker/daemon.json. | boolean | true |
| setAsDefault | Set nvidia as the default container runtime in Docker daemon. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/minato-ryan/devcontainer-features/blob/main/src/docker-in-docker-nvidia/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
