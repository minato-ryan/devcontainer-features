
# NVIDIA Container Toolkit (nvidia-container)

Installs the NVIDIA Container Toolkit and configures container runtimes (such as Docker) for NVIDIA GPU support.

## Example Usage

```json
"features": {
    "ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Select or enter an NVIDIA Container Toolkit version (e.g. 'latest' or '1.20.1'). | string | latest |
| configureDocker | Register the nvidia runtime in /etc/docker/daemon.json. | boolean | true |
| setAsDefault | Set nvidia as the default container runtime in Docker daemon. | boolean | false |

## Container Runtime Requirement

This feature only installs the **NVIDIA Container Toolkit** and configures container runtimes (such as Docker daemon) if present. It **does not** install Docker or any container engine itself.

You must install a container runtime separately in your dev container. For example, you can combine this feature with the [Docker-in-Docker](https://github.com/devcontainers/features/tree/main/src/docker-in-docker) feature (`ghcr.io/devcontainers/features/docker-in-docker`):

```json
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/devcontainers/features/docker-in-docker:2": {},
        "ghcr.io/minato-ryan/devcontainer-features/nvidia-container:1": {}
    }
}
```


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/minato-ryan/devcontainer-features/blob/main/src/nvidia-container/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
