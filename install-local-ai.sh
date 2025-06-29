#!/bin/bash

# Parse -s option for remote transfer
if [[ "$@" == *"-s "* ]]; then
  while getopts "s:" opt; do
    case $opt in
      s)
        remote_host="$OPTARG"
        scp "$0" "$remote_host:~/$(basename "$0")"
        echo "File transferred to $remote_host:~/$(basename "$0")"
        exit 0
        ;;
      *)
        echo "Usage: $0 [-s user@host]" >&2
        exit 1
        ;;
    esac
  done
  shift $((OPTIND -1))
fi

REBOOT_COUNT_FILE="./reboot_count"

# Clear the reboot count file if -c is used
if [[ "$@" == *"-c"* ]]; then
  rm -f "$REBOOT_COUNT_FILE"
  echo "Reboot count file cleared."
  exit 0
fi

#make a persistent files tokeep track of reboots and make a variable to hold the reboot count
if [ ! -f "$REBOOT_COUNT_FILE" ]; then
  echo 0 > "$REBOOT_COUNT_FILE"
fi

reboot_count=$(cat "$REBOOT_COUNT_FILE")
reboot_count=$((reboot_count + 1))
echo $reboot_count > "$REBOOT_COUNT_FILE"
echo "Reboot count: $reboot_count"

if [ "$reboot_count" -eq 1 ]; then
  #Update
  sudo apt-get update -y && sudo apt-get upgrade -y

  #Install Docker
  #https://docs.docker.com/engine/install/ubuntu/

  sudo apt-get update
  sudo apt-get install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y

  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

  # Install Nvidia Container Toolkit
  # https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installation

  if ! lspci | grep -i nvidia > /dev/null; then
    echo "Error: No NVIDIA GPU detected." >&2
    exit 1
  fi

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  sudo apt-get update -y

  export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
    sudo apt-get install -y \
        nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
        libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

  #Install Nvidia Drivers
  sudo apt update -y && sudo apt upgrade -y
  ubuntu-drivers devices | grep recommended
  # Install the recommended driver
  sudo ubuntu-drivers autoinstall

  sudo reboot now
fi

#Second reboot
if [ "$reboot_count" -eq 2 ]; then

  # GPU tools
  sudo apt  install nvtop -y
  sudo apt install net-tools -y

  # Keep Xorg from using the GPU
  #sudo truncate -s 0 /usr/share/X11/xorg.conf.d/10-nvidia.conf
  #sudo systemctl restart display-manager

  # Configure Docker to use Nvidia driver
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker

  #Install Ollama
  curl -fsSL https://ollama.com/install.sh | sh

  # Add ExecStartPre to Ollama systemd service
  OLLAMA_SERVICE="/etc/systemd/system/ollama.service"
  if [ -f "$OLLAMA_SERVICE" ]; then
    sudo sed -i '/^\[Service\]/a ExecStartPre=/bin/sleep 15' "$OLLAMA_SERVICE"
    sudo systemctl daemon-reload
    echo "Added ExecStartPre=/bin/sleep 15 to $OLLAMA_SERVICE"
  else
    echo "Warning: $OLLAMA_SERVICE not found. Skipping ExecStartPre addition."
  fi

  ollama pull gemma3

  #https://github.com/open-webui/open-webui/discussions/4376
  sudo docker run -d -p 3000:8080 --gpus all --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:cuda
  sudo reboot now
fi

printf "Installation complete\n"
