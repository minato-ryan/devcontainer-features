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
