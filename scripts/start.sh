#!/usr/bin/env bash
# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

check_cuda_version() {
    echo "Checking CUDA version using nvidia-smi..."

    CURRENT_CUDA_VERSION=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9.]+")

    if [[ -z "${CURRENT_CUDA_VERSION}" ]]; then
        echo "CUDA version not found. Make sure that CUDA is properly installed and 'nvidia-smi' is available."
        exit 1
    fi

    echo "Detected CUDA version using nvidia-smi: ${CURRENT_CUDA_VERSION}"

    IFS='.' read -r -a CURRENT_CUDA_VERSION_ARRAY <<< "${CURRENT_CUDA_VERSION}"
    CURRENT_CUDA_VERSION_MAJOR="${CURRENT_CUDA_VERSION_ARRAY[0]}"
    CURRENT_CUDA_VERSION_MINOR="${CURRENT_CUDA_VERSION_ARRAY[1]}"

    IFS='.' read -r -a REQUIRED_CUDA_VERSION_ARRAY <<< "${REQUIRED_CUDA_VERSION}"
    REQUIRED_CUDA_VERSION_MAJOR="${REQUIRED_CUDA_VERSION_ARRAY[0]}"
    REQUIRED_CUDA_VERSION_MINOR="${REQUIRED_CUDA_VERSION_ARRAY[1]}"

    if [[ "${CURRENT_CUDA_VERSION_MAJOR}" -lt "${REQUIRED_CUDA_VERSION_MAJOR}" ||
          ( "${CURRENT_CUDA_VERSION_MAJOR}" -eq "${REQUIRED_CUDA_VERSION_MAJOR}" && "${CURRENT_CUDA_VERSION_MINOR}" -lt "${REQUIRED_CUDA_VERSION_MINOR}" ) ]]; then
        echo "Current CUDA version (${CURRENT_CUDA_VERSION}) is older than required (${REQUIRED_CUDA_VERSION})."
        echo "Please switch to a pod with CUDA version ${REQUIRED_CUDA_VERSION} or higher."
        exit 1
    else
        echo "CUDA version from nvidia-smi seems sufficient: ${CURRENT_CUDA_VERSION}"
    fi
}

test_pytorch_cuda() {
    echo "Performing a simple CUDA functionality test using PyTorch..."

    python3 - <<END
import sys
import torch

try:
    if not torch.cuda.is_available():
        print("CUDA is not available on this system.")
        sys.exit(1)

    cuda_version = torch.version.cuda
    if cuda_version is None:
        print("Could not determine CUDA version using PyTorch.")
        sys.exit(1)

    print(f"From PyTorch test, your CUDA version meets the requirement: {cuda_version}")
    num_gpus = torch.cuda.device_count()
    print(f"Number of CUDA-capable devices: {num_gpus}")

    for i in range(num_gpus):
        print(f"Device {i}: {torch.cuda.get_device_name(i)}")

except RuntimeError as e:
    print(f"Runtime error: {e}")
    sys.exit(2)
except Exception as e:
    print(f"An unexpected error occurred: {e}")
    sys.exit(1)
END

    if [[ $? -ne 0 ]]; then
        echo "PyTorch CUDA test failed. Please switch to a pod with a proper CUDA setup."
        exit 1
    else
        echo "CUDA version is sufficient and functional."
    fi
}

start_nginx() {
    echo "NGINX: Starting Nginx service..."
    service nginx start
}

execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

generate_ssh_host_keys() {
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
        ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
        ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
    fi
}

setup_ssh() {
    echo "SSH: Setting up SSH..."
    mkdir -p ~/.ssh

    if [[ ${PUBLIC_KEY} ]]; then
        echo -e "${PUBLIC_KEY}\n" >> ~/.ssh/authorized_keys
    fi

    chmod 700 -R ~/.ssh
    generate_ssh_host_keys
    service ssh start

    echo "SSH: Host keys:"
    cat /etc/ssh/*.pub
}

export_env_vars() {
    echo "ENV: Exporting environment variables..."
    printenv | grep -E '^RUNPOD_|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

start_jupyter() {
    echo "JUPYTER: Starting Jupyter Lab..."
    mkdir -p /workspace/logs
    cd / && \
    nohup jupyter lab --allow-root \
      --no-browser \
      --port=8888 \
      --ip=* \
      --FileContentsManager.delete_to_trash=False \
      --ContentsManager.allow_hidden=True \
      --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
      --ServerApp.token=${JUPYTER_LAB_PASSWORD} \
      --ServerApp.allow_origin=* \
      --ServerApp.preferred_dir=/workspace &> /workspace/logs/jupyter.log &
    echo "JUPYTER: Jupyter Lab started"
}

start_code_server() {
    echo "CODE-SERVER: Starting Code Server..."
    mkdir -p /workspace/logs
    nohup code-server \
        --bind-addr 0.0.0.0:7777 \
        --auth none \
        --enable-proposed-api true \
        --disable-telemetry \
        /workspace &> /workspace/logs/code-server.log &
    echo "CODE-SERVER: Code Server started"
}

start_runpod_uploader() {
    echo "RUNPOD-UPLOADER: Starting RunPod Uploader..."
    nohup /usr/local/bin/runpod-uploader &> /workspace/logs/runpod-uploader.log &
    echo "RUNPOD-UPLOADER: RunPod Uploader started"
}

update_rclone() {
    echo "RCLONE: Updating rclone..."
    rclone selfupdate
}

start_cron() {
    echo "CRON: Starting Cron service..."
    service cron start
}

check_python_version() {
    echo "PYTHON: Checking Python version..."
    python3 -V
}

#!/usr/bin/env bash
# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# (Most functions unchanged - kept as-is for context)
# Skipping unchanged ones like check_cuda_version, test_pytorch_cuda, etc.

start_forge() {
    echo "FORGE: Setting up and launching..."

    FORGE_DIR="/workspace/stable-diffusion-webui"

    echo "Testing GitHub connectivity..."
    ping -c 1 github.com || echo "⚠️  GitHub DNS not resolving!"

    if [ ! -d "$FORGE_DIR" ]; then
        echo "Cloning Forge Stable Diffusion WebUI..."
        git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "$FORGE_DIR"
    fi

    cd "$FORGE_DIR"

    if [ ! -d "venv" ]; then
        echo "Creating Forge venv..."
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip

        if [ -f requirements_versions.txt ]; then
            pip install -r requirements_versions.txt
        else
            echo "⚠️  WARNING: requirements_versions.txt not found. Skipping base requirements."
        fi

        echo "Installing Forge extensions..."
        git clone --depth=1 https://codeberg.org/Gourieff/sd-webui-reactor.git extensions/sd-webui-reactor
        git clone --depth=1 https://github.com/zanllp/sd-webui-infinite-image-browsing.git extensions/infinite-image-browsing
        git clone --depth=1 https://github.com/civitai/sd_civitai_extension.git extensions/sd_civitai_extension
        git clone --depth=1 https://github.com/BlafKing/sd-civitai-browser-plus.git extensions/sd-civitai-browser-plus

        echo "Installing all Forge extension dependencies in one pip call..."
        pip install -r extensions/sd-webui-reactor/requirements.txt \
                    -r extensions/infinite-image-browsing/requirements.txt \
                    -r extensions/sd_civitai_extension/requirements.txt \
                    onnxruntime-gpu send2trash beautifulsoup4 ZipUnicode fake-useragent packaging pysocks

        deactivate
    fi

    echo "Launching Forge WebUI..."
    source "${FORGE_DIR}/venv/bin/activate"
    nohup python launch.py --listen --port 3000 --api --enable-insecure-extension-access --cuda-malloc --opt-sdp-attention &> /workspace/logs/forge.log &
    deactivate
}

start_comfyui() {
    echo "COMFYUI: Setting up and launching..."

    COMFY_DIR="/workspace/comfyui"
    CUSTOM_NODES_DIR="${COMFY_DIR}/custom_nodes"

    if [ ! -d "$COMFY_DIR" ]; then
        echo "Cloning ComfyUI..."
        git clone https://github.com/tbrewer409/ComfyRepo.git "$COMFY_DIR"
    fi

    cd "$COMFY_DIR"

    if [ ! -d "venv" ]; then
        echo "Creating ComfyUI venv..."
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install -r requirements.txt

        echo "Installing ComfyUI extensions..."

        mkdir -p "$CUSTOM_NODES_DIR"

        # Clone extensions (no parsing, just straight-up Forge-style)
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$CUSTOM_NODES_DIR/ComfyUI-Manager"
        git clone https://github.com/rgthree/rgthree-comfy.git "$CUSTOM_NODES_DIR/rgthree-comfy"
        git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack"
        git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git "$CUSTOM_NODES_DIR/comfyui_controlnet_aux"
        git clone https://github.com/yolain/ComfyUI-Easy-Use.git "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use"
        git clone https://github.com/kijai/ComfyUI-Florence2.git "$CUSTOM_NODES_DIR/ComfyUI-Florence2"
        git clone https://github.com/WASasquatch/was-node-suite-comfyui.git "$CUSTOM_NODES_DIR/was-node-suite-comfyui"
        git clone https://github.com/cubiq/ComfyUI_essentials.git "$CUSTOM_NODES_DIR/ComfyUI_essentials"
        git clone https://github.com/Jonseed/ComfyUI-Detail-Daemon.git "$CUSTOM_NODES_DIR/ComfyUI-Detail-Daemon"
        git clone https://codeberg.org/Gourieff/comfyui-reactor-node.git "$CUSTOM_NODES_DIR/comfyui-reactor-node"
        git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git "$CUSTOM_NODES_DIR/ComfyUI_JPS-Nodes"
        git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git "$CUSTOM_NODES_DIR/ComfyUI_Comfyroll_CustomNodes"
        git clone https://github.com/theUpsider/ComfyUI-Logic.git "$CUSTOM_NODES_DIR/ComfyUI-Logic"

        # Install all extension requirements in one pip call
        echo "Installing all ComfyUI extension requirements in one pip call..."
        pip install \
            -r "$CUSTOM_NODES_DIR/ComfyUI-Manager/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/rgthree-comfy/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/comfyui_controlnet_aux/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/ComfyUI-Florence2/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/was-node-suite-comfyui/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/ComfyUI_essentials/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/ComfyUI-Detail-Daemon/requirements.txt" \
            -r "$CUSTOM_NODES_DIR/comfyui-reactor-node/requirements.txt"

        deactivate
    fi

    echo "Launching ComfyUI..."
    source "$COMFY_DIR/venv/bin/activate"
    nohup python main.py --listen 0.0.0.0 --port 7860 \
        --extra-model-paths-config /workspace/comfyui/extra_model_paths.yaml \
        --highvram --cuda-malloc &> /workspace/logs/comfyui.log &
    deactivate
}




# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

echo "Container Started, configuration in progress..."
start_nginx
setup_ssh
start_cron
start_jupyter
start_runpod_uploader
start_code_server
execute_script "/pre_start.sh" "PRE-START: Running pre-start script..."
update_rclone
check_python_version
export_env_vars
start_forge
start_comfyui
execute_script "/post_start.sh" "POST-START: Running post-start script..."
echo "Container is READY!"
sleep infinity
