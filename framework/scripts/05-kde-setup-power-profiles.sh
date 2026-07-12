#!/bin/bash
# 05-kde-setup-power-profiles.sh — Apply AC/Battery power profile defaults, install gpu-switch, and set default iGPU

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

echo "=== Phase 4: Setting up KDE Power Profiles and GPU Switching ==="

# 1. Apply Powerdevil configs (AC / Battery settings)
if [[ -f "$HOME_CONFIGS/.config/powerdevilrc" ]]; then
    echo "Copying custom powerdevilrc config to ~/.config/powerdevilrc..."
    mkdir -p "$HOME/.config"
    cp "$HOME_CONFIGS/.config/powerdevilrc" "$HOME/.config/powerdevilrc"
else
    echo "Warning: Powerdevil configuration template not found at $HOME_CONFIGS/.config/powerdevilrc."
    echo "Using default power profile behavior."
fi

# 2. Deploy and install the gpu-switch script
echo "Installing gpu-switch utility..."
mkdir -p "$HOME/.local/bin"
if [[ -f "$CUSTOM_CONFIGS/bin/gpu-switch" ]]; then
    cp "$CUSTOM_CONFIGS/bin/gpu-switch" "$HOME/.local/bin/gpu-switch"
    chmod +x "$HOME/.local/bin/gpu-switch"
    echo "gpu-switch utility successfully installed to ~/.local/bin/gpu-switch."
else
    echo "Error: Source gpu-switch script not found at $CUSTOM_CONFIGS/bin/gpu-switch."
    exit 1
fi

# 3. Initialize default-GPU configuration as AMD (iGPU)
echo "Initializing default GPU to AMD (iGPU)..."
"$HOME/.local/bin/gpu-switch" amd

# 4. Print GPU information for verification
echo ""
echo "Current GPU offload provider list (via switcherooctl):"
if command -v switcherooctl &>/dev/null; then
    switcherooctl list || true
else
    echo "switcherooctl utility is not installed."
fi

echo "Power profile and GPU setup complete. Please restart your KDE Plasma session to apply default GPU settings."
