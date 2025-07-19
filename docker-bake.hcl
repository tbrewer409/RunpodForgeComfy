variable "REGISTRY" {
    default = "docker.io"
}

variable "REGISTRY_USER" {
    default = "tbrewer937"
}

variable "RELEASE" {
    default = "1.0.5"
}

variable "RUNPODCTL_VERSION" {
    default = "v1.14.4"
}

group "default" {
    targets = [
        "py310-cu124-torch250"
    ]
}

target "py310-cu124-torch250" {
    dockerfile = "./dockerfiles/with-xformers-cuxxx/Dockerfile"
    tags = ["${REGISTRY}/${REGISTRY_USER}/forge_comfyui:${RELEASE}"]
    args = {
        BASE_IMAGE = "nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04"
        REQUIRED_CUDA_VERSION = "12.4"
        PYTHON_VERSION = "3.10"
        RELEASE = "${RELEASE}"
        INDEX_URL = "https://download.pytorch.org/whl/cu124"
        TORCH_VERSION = "2.5.0+cu124"
        XFORMERS_VERSION = "0.0.28.post2"
        RUNPODCTL_VERSION = "${RUNPODCTL_VERSION}"
    }

    platforms = ["linux/amd64"]
    annotations = ["org.opencontainers.image.authors=${REGISTRY_USER}"]
}
