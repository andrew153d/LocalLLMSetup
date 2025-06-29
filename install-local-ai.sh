
#!/bin/bash

# install-local-ai.sh
# Script to automate installation of Docker, NVIDIA drivers, NVIDIA Container Toolkit, Ollama, and Open WebUI for local LLM setup.
# Supports remote transfer (-s user@host) and reboot tracking for multi-stage installation.

set -euo pipefail

REBOOT_COUNT_FILE="./reboot_count"

usage() {
  echo "Usage: $0 [-s user@host] [-c]" >&2
  echo "  -s user@host   Transfer this script to a remote host via scp and exit."
  echo "  -c            Clear the reboot count file and exit."
  exit 1
}

# Parse options
while getopts "s:c" opt; do
  case $opt in
    s)
      remote_host="$OPTARG"
      scp "$0" "$remote_host:~/$(basename "$0")"
      echo "File transferred to $remote_host:~/$(basename "$0")"
      exit 0
      ;;
    c)
      rm -f "$REBOOT_COUNT_FILE"
      echo "Reboot count file cleared."
      exit 0
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND - 1))

# Initialize reboot count file if it doesn't exist
if [ ! -f "$REBOOT_COUNT_FILE" ]; then
  echo 0 > "$REBOOT_COUNT_FILE"
fi

# Increment and store reboot count
reboot_count=$(<"$REBOOT_COUNT_FILE")
reboot_count=$((reboot_count + 1))
echo "$reboot_count" > "$REBOOT_COUNT_FILE"
echo "Reboot count: $reboot_count"

if [ "$reboot_count" -eq 1 ]; then
  echo "[Stage 1] Installing Docker and NVIDIA Container Toolkit..."
  sudo apt-get update -y && sudo apt-get upgrade -y

  # Install Docker
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Check for NVIDIA GPU
  if ! lspci | grep -i nvidia > /dev/null; then
    echo "Error: No NVIDIA GPU detected." >&2
    exit 1
  fi

  # Install NVIDIA Container Toolkit
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
  sudo apt-get update -y
  export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
  sudo apt-get install -y \
    nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

  # Install NVIDIA drivers
  sudo apt-get update -y && sudo apt-get upgrade -y
  echo "Detecting recommended NVIDIA driver..."
  ubuntu-drivers devices | grep recommended
  sudo ubuntu-drivers autoinstall

  echo "[Stage 1] Complete. Rebooting..."
  sudo reboot now
fi

if [ "$reboot_count" -eq 2 ]; then
  echo "[Stage 2] Post-reboot: GPU tools, Docker config, Ollama, and Open WebUI..."
  sudo apt-get install -y nvtop net-tools

  # Configure Docker to use NVIDIA runtime
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker

  # Install Ollama
  curl -fsSL https://ollama.com/install.sh | sh

  # Add ExecStartPre to Ollama systemd service for startup delay
  OLLAMA_SERVICE="/etc/systemd/system/ollama.service"
  if [ -f "$OLLAMA_SERVICE" ]; then
    sudo sed -i '/^\[Service\]/a ExecStartPre=/bin/sleep 15' "$OLLAMA_SERVICE"
    sudo systemctl daemon-reload
    echo "Added ExecStartPre=/bin/sleep 15 to $OLLAMA_SERVICE"
  else
    echo "Warning: $OLLAMA_SERVICE not found. Skipping ExecStartPre addition."
  fi

  # Pull Ollama model
  ollama pull gemma3

  # Start Open WebUI with GPU support
  sudo docker run -d -p 3000:8080 --gpus all --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:cuda

  echo "[Stage 2] Complete. Rebooting..."
  sudo reboot now
fi

echo "Installation complete."
