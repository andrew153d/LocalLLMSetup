
# LocalLLMSetup

A fully automated script to set up a local Large Language Model (LLM) environment with [Ollama](https://ollama.com/) and [Open WebUI](https://github.com/open-webui/open-webui) on an Ubuntu-based system (ideal for Proxmox VMs with NVIDIA GPUs).

## Features

- **Automated installation** of Docker, NVIDIA drivers, and NVIDIA Container Toolkit
- **Ollama** LLM runtime installation and configuration
- **Open WebUI** deployment with GPU support via Docker
- **Persistent reboot tracking** to handle multi-stage installation
- **Remote script transfer** and reboot count reset options

## Prerequisites

- Ubuntu 20.04+ (tested on Ubuntu, may work on Debian-based systems)
- An NVIDIA GPU (required for GPU acceleration)
- Sudo privileges

## Usage

1. **Clone this repository:**
   ```bash
   git clone https://github.com/yourusername/LocalLLMSetup.git
   cd LocalLLMSetup
   ```

2. **Run the installation script:**
   ```bash
   chmod +x install-local-ai.sh
   ./install-local-ai.sh
   ```
   > **Note:** The script will automatically reboot your system twice to complete all installation steps. After each reboot, re-run the script until you see "Installation complete".

3. **Access Open WebUI:**
   - Open your browser and go to [http://localhost:3000](http://localhost:3000)

## Script Options

- `-s user@host` : Transfer the script to a remote host via `scp` and exit.
- `-c` : Clear the reboot count and start the installation from scratch.

## What the Script Does

- **First Run:**
  - Updates the system and installs Docker
  - Installs NVIDIA Container Toolkit and drivers
  - Reboots the system

- **Second Run:**
  - Installs GPU monitoring tools (`nvtop`)
  - Configures Docker for NVIDIA runtime
  - Installs Ollama and pulls the `gemma3` model
  - Deploys Open WebUI with GPU support
  - Reboots the system

- **Final Run:**
  - Confirms installation is complete

## Troubleshooting

- Ensure your VM has a compatible NVIDIA GPU and virtualization supports GPU passthrough.
- If you encounter issues, clear the reboot count with `./install-local-ai.sh -c` and try again.

## License

MIT License
