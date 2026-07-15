# Fedora Reinstall Framework & OS Configurations


## About

Establish a self-contained, automated reinstall framework inside the `os-configs` repository. Following a fresh install of Fedora Workstation (KDE Plasma), use this guide to restore system configurations, services, user profiles, power settings, and automated backup timers.

---

## Table of Contents
*   [1. Directory Layout](#1-directory-layout)
*   [2. Reinstall Execution Flow](#2-reinstall-execution-flow)
    *   [Phase 1: Bootstrapping (Manual Setup)](#phase-1-bootstrapping-manual-setup)
        *   [0. Partition Setup & Formatting](#0-partition-setup--formatting)
        *   [1. Mount Storage Drives via fstab Labels](#1-mount-storage-drives-via-fstab-labels)
    *   [Keys & Local Identity Setup](#keys--local-identity-setup)
    *   [First-Time Environment Initialization](#first-time-environment-initialization)
    *   [Phase 2: OS Configuration & Core Upgrades](#phase-2-os-configuration--core-upgrades)
    *   [Phase 3: Core Setup & System Snapshots](#phase-3-core-setup--system-snapshots)
    *   [Phase 4: Applications & Customizations](#phase-4-applications--customizations)
*   [3. Manual Installations & Third-Party Tools](#3-manual-installations--third-party-tools)

---

## 1. Directory Layout

```text
os-configs/
├── framework/               # Framework orchestration and scripts
│   ├── scripts/             # Sequential setup scripts (run manually)
│   ├── configs/             # Configuration declarations (.conf and .env)
│   └── automation/          # Periodic backup scripts and systemd units
├── init/                    # Fresh environment default templates
├── keys/                    # Sensitive local keys (gitignored)
└── user-configs/            # System deployment configuration profiles
    ├── custom/              # Custom shell variables and login profiles (.profile)
    ├── home/                # Files copied directly to user home directory (~/)
    └── system/              # Configuration files copied to /etc (requires sudo)
```

---

## 2. Reinstall Execution Flow

```text
[Fresh Fedora Install] ➔ [Phase 1: Bootstrapping] ➔ [Phase 2: Post-Install & Drivers]
                                                          │
                                                    [REBOOT 1: Enroll Keys & GPU]
                                                          │
                                                          ▼
[Verification & Done] 🠔 [Phase 4: Apps & Automation] 🠔 [Phase 3: Configs & Snapshots]
                                                          ▲
                                                    [REBOOT 2: Verify Snapshots in GRUB]
```

### Tag Conventions
*   `[CAUTION]`: Actions affecting system boot partition flags, mounts, or secure states.
*   `[REFINE]`: Manual actions required to customize values prior to running scripts.

---

### Phase 1: Bootstrapping (Manual Setup)

> **[CAUTION]**
> These initial setup steps are completed manually on your fresh Fedora install before the repository is cloned.

#### 0. [CAUTION] Partition Setup & Formatting
If you only formatted your root partition during install and your other data partitions exist, skip this step.

*   **Check existing disks and free space:**
    ```shell
    lsblk -o MODEL,NAME,LABEL,SIZE,FSTYPE,MOUNTPOINT
    sudo parted /dev/sda unit GB print free # Replace /dev/sda with your target disk
    ```
*   **Format and Label Partitions:** Unmount first (`sudo umount <path>`), partition, and apply ext4 labels:
    ```shell
    # Define variables (customize disk and sizes as needed)
    DISK="/dev/sda"                   # Target disk device
    PARTITION_LABEL1="core"
    PARTITION_SIZE1=200                # Size in GiB
    PARTITION_OFFSET1="0%"             # Start offset
    
    PARTITION_LABEL2="library"
    PARTITION_SIZE2=600                # Size in GiB
    PARTITION_OFFSET2=$PARTITION_SIZE1 # Start offset
    
    PARTITION_LABEL3="temp"
    PARTITION_SIZE3=100                # Size in GiB
    PARTITION_OFFSET3=$((PARTITION_SIZE1 + PARTITION_SIZE2)) # Start offset
    
    # Wipe disk partition table
    sudo parted $DISK mklabel gpt
    
    # Partition the disk (specifying absolute start and end offsets)
    sudo parted -a optimal $DISK mkpart $PARTITION_LABEL1 "${PARTITION_OFFSET1}" "${PARTITION_SIZE1}GiB"
    sudo parted -a optimal $DISK mkpart $PARTITION_LABEL2 "${PARTITION_OFFSET2}GiB" "$((PARTITION_OFFSET2 + PARTITION_SIZE2))GiB"
    sudo parted -a optimal $DISK mkpart $PARTITION_LABEL3 "${PARTITION_OFFSET3}GiB" "100%"
    
    # Resolve partition device prefix (e.g. /dev/nvme0n1p1 vs /dev/sda1)
    if [[ "$DISK" =~ "nvme" ]]; then
        PART_PREFIX="${DISK}p"
    else
        PART_PREFIX="$DISK"
    fi
    
    # Format ext4 with system labels:
    sudo mkfs.ext4 -L $PARTITION_LABEL1 "${PART_PREFIX}1"
    sudo mkfs.ext4 -L $PARTITION_LABEL2 "${PART_PREFIX}2"
    sudo mkfs.ext4 -L $PARTITION_LABEL3 "${PART_PREFIX}3"
    ```
*   **Shrink Existing Partition:** Check and resize safely:
    ```shell
    DISK="/dev/sda"                   # Target disk device
    
    # Resolve partition device prefix (e.g. /dev/nvme0n1p1 vs /dev/sda1)
    if [[ "$DISK" =~ "nvme" ]]; then
        PART_PREFIX="${DISK}p"
    else
        PART_PREFIX="$DISK"
    fi
    
    PARTITION_NAME="${PART_PREFIX}1"
    PARTITION_SIZE="200"              # Target size in GiB (aligned with resize2fs)
    
    # Check filesystem, shrink filesystem to 200 GiB, then shrink partition using GiB unit
    sudo e2fsck -f -y "$PARTITION_NAME" && sudo resize2fs "$PARTITION_NAME" "${PARTITION_SIZE}G"
    sudo parted -s "$DISK" unit GiB resizepart 1 "$PARTITION_SIZE"
    ```

#### 1. Mount Storage Drives via fstab Labels
Create mount paths and append entries to `/etc/fstab` using `LABEL=` so they survive partition changes:
```shell
sudo mkdir -p /mnt/{core,library,temp}
# Append the following lines to /etc/fstab:
LABEL=core    /mnt/core    ext4    defaults,noatime    0    2
LABEL=library /mnt/library ext4    defaults,noatime    0    2
LABEL=temp    /mnt/temp    ext4    defaults,noatime    0    2
```
Mount directories and take user ownership:
```shell
sudo mount -a && sudo chown -R $USER:$USER /mnt/{core,library,temp}
```

#### 2. Install Bootstrap Prerequisites
Install the bare minimum tools needed to authenticate, configure snapper, and clone files:
```shell
sudo dnf install -y git gh ksshaskpass p7zip p7zip-plugins rclone snapper
```

#### 3. SSH Setup
*   **Scenario A — Restoring existing keys** (if keys already exist in `/mnt/core/os-configs/keys/ssh/`):
    ```shell
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    cp /mnt/core/os-configs/keys/ssh/id_ed25519* ~/.ssh/
    chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub
    ```
*   **Scenario B — First-time setup** (generating a new keypair):
    ```shell
    mkdir -p /mnt/core/os-configs/keys/ssh
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f /mnt/core/os-configs/keys/ssh/id_ed25519
    cp /mnt/core/os-configs/keys/ssh/id_ed25519* ~/.ssh/
    chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub
    ```

Configure SSH client settings to use the key:
```shell
echo -e "Host github.com\n    IdentityFile ~/.ssh/id_ed25519\n    AddKeysToAgent yes" > ~/.ssh/config
```

#### 4. Verify the Native SSH Agent Session
Fedora KDE automatically initializes an `ssh-agent` and exports its socket on login. To verify it is running in your active terminal session:
```shell
echo $SSH_AUTH_SOCK
```
*Because you configured `AddKeysToAgent yes` in step 3, your private key will be loaded into this agent automatically the very first time you type your passphrase during a git or ssh command.*

#### 5. Authenticate GitHub CLI & Clone Repository
Add your SSH key to GitHub and clone the repository:
```shell
gh auth login
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
ssh -T git@github.com # Verify connection
gh repo clone <github-username>/os-configs /mnt/core/os-configs
```

---

### Keys & Local Identity Setup
The `keys/` directory contains local security credentials and environment identities. It is ignored by Git in `.gitignore` and **must never** be committed or pushed to public repositories.

1.  **Configure identity.env:**
    Copy `init/configs/identity.env.default` to `keys/identity.env` and edit it with your details:
    ```bash
    # Git configuration credentials
    export GIT_USER_EMAIL="your-email@example.com"    # Populates global user.email via 01-restore-configs.sh
    export GIT_USER_NAME="Your Full Name"            # Populates global user.name via 01-restore-configs.sh
    
    # GitHub user handle
    export GITHUB_USERNAME="your-github-username"    # GitHub account user handle
    ```
2.  **Store SSH Keys:**
    Place your private and public SSH keys (`id_ed25519` and `id_ed25519.pub`) inside `keys/ssh/` so they can be securely restored.

---

### First-Time Environment Initialization

> **[REFINE]**
> Perform these steps if setting up `os-configs` for the very first time.

Initialize default configuration templates from the root of the repository:
```shell
cd /mnt/core/os-configs
# Initialize all templates:
bash init/00-init-generate-defaults.sh --all

# Or initialize specific parts selectively using flags:
#   --git      : Generate user-configs/home/.gitconfig
#   --ssh      : Generate user-configs/home/.ssh/config
#   --profile  : Generate user-configs/custom/.profile
#   --dnf      : Generate user-configs/system/dnf/dnf.conf
#   --snapper  : Generate user-configs/system/snapper/configs/root
#   --power    : Generate user-configs/home/.config/powerdevilrc
#   --identity : Generate keys/identity.env
```

---

### Phase 2: OS Configuration & Core Upgrades

#### 6. DNF Optimization and Repo Setup Script
Updates system packages, deploys optimized DNF settings, enables RPM Fusion and Terra:
```shell
bash framework/scripts/00-dnf-post-install.sh
```

#### 7. GPU Setup & Secure Boot Key Enrollment
*   **AMD (iGPU):** mesa/RADV drivers run natively. Verify output of `glxinfo | grep "OpenGL renderer"`.
*   **NVIDIA (dGPU):** Install drivers:
    ```shell
    sudo dnf install akmod-nvidia
    ```
*   **`[CRITICAL]` Secure Boot driver signing:** If Secure Boot is enabled in your BIOS, you **must** enroll your signature key to allow the NVIDIA driver to load:
    ```shell
    sudo kmodgenca -a                                              # Generate signature key
    sudo mokutil --import /etc/pki/akmods/certs/public_key.der     # Register MOK key
    # Enter a temporary password when prompted
    ```

> [!CAUTION]
> **DO NOT SKIP THE BLUE MOK SCREEN ON REBOOT!**
> 1. When the laptop restarts, it will show a blue screen titled **"Shim UEFI key management"** or **"MOK Manager"**.
> 2. You **must** select **"Enroll MOK"** -> **"Continue"** -> **"Yes"** -> enter the temporary password you defined above.
> 3. Select **"Reboot"** to finish.
> 
> *If you skip this blue screen or hit any key to continue default boot, the kernel will refuse to load the unsigned NVIDIA driver on boot, locking you at a black boot-loop screen.*

**═══ PERFORM REBOOT 1 (Enrolls Secure Boot Keys & Loads GPU Kernel Modules) ═══**

---

### Phase 3: Core Setup & System Snapshots

#### 8. Restore Configuration Profiles
Parse `restore.conf` and copy config profiles to their relative home and system locations:
```shell
cd /mnt/core/os-configs
bash framework/scripts/01-restore-configs.sh
```

#### 9. `[CAUTION]` Set Up Snapper and GRUB Rollback Configuration (Fedora Only)
Generates root snapshot rules, optimizes timeline retention limits, and configures GRUB boot submenus:
> **[NOTE]**
> This script is tailored specifically for Fedora's single BTRFS subvolume layout and deploys an override drop-in for systemd path unit dependencies.
```shell
bash framework/scripts/02-snapper-btrfs-fedora.sh
```

#### 10. Deploy Desktop Settings
Deploys custom KDE Powerdevil configurations for screen dimming and auto-suspend timeouts on AC vs. Battery:
```shell
bash framework/scripts/05-kde-setup-power-profiles.sh
```

*   **AC Power Profile defaults:**
    *   Dim display when idle: **10 minutes** (`DimDisplayWhenIdleTimeoutSec=600`)
    *   Turn off display when idle: **15 minutes** (`TurnOffDisplayWhenIdleTimeoutSec=900`)
    *   Auto-suspend: **Disabled** (`AutoSuspendAction=0`)
*   **Battery Power Profile defaults:**
    *   Dim display when idle: **5 minutes** (`DimDisplayWhenIdleTimeoutSec=300`)
    *   Turn off display when idle: **10 minutes** (`TurnOffDisplayWhenIdleTimeoutSec=600`)
    *   Auto-suspend: **20 minutes** (`AutoSuspendTimeoutSec=1200`, `AutoSuspendAction=1`)


#### 11. `[CAUTION]` Configure Google Drive Mount (Rclone)
Configure rclone Google Drive credentials and mount parameters:
```shell
rclone config # Select new remote, name it 'gdrive', and authenticate with your account
```
> **[REFINE]**
> Sensitive credentials, OAuth Client IDs, and Access tokens will reside inside `~/.config/rclone/rclone.conf` which is backed up.
```shell
bash framework/scripts/06-setup-rclone-gdrive.sh # Add rclone mount config to fstab
```

#### 12. Enable Automation Background Timers
Deploys and activates weekly configuration synchronization timers:
```shell
bash framework/scripts/07-enable-services.sh
```
*   `os-configs-sync.timer` (**enabled automatically**): Runs weekly to commit local configuration changes to your git repository.
*   `os-configs-gdrive.timer` (**disabled by default**): Optional weekly timer to compress configuration files and upload them to Google Drive. To enable it, run:
    ```shell
    systemctl --user enable --now os-configs-gdrive.timer
    ```

**═══ PERFORM REBOOT 2 (Verifies Bootloader Menu, Snapshots, and Active Services) ═══**

---

### Phase 4: Applications & Customizations

#### 13. Install Applications
Sequentially install DNF packages, Flatpaks, and enforce sandboxed permissions overrides:
```shell
cd /mnt/core/os-configs
# Option A — Install required & daily driver applications (Default):
sudo bash framework/scripts/03-fedora-install-packages.sh --daily

# Option B — Install only development DNF and Flatpak packages (includes VS Code):
sudo bash framework/scripts/03-fedora-install-packages.sh --dev

# Option C — Install all package sections:
sudo bash framework/scripts/03-fedora-install-packages.sh --all
```

#### 14. Purge System Bloatware
Remove listed default games, Akonadi organizers, and redundant applications:
```shell
bash framework/scripts/04-fedora-uninstall-bloat.sh
```

#### 15. Run Diagnostic Verification Suite
Check system integrity and verify configurations (reports status results without modifying anything):
```shell
# Run verification checks (add --dev flag if you installed development packages):
bash framework/scripts/08-verify-setup.sh [--dev]
```

---

## 3. Manual Installations & Third-Party Tools

These applications require manual scripts, external tarballs, or standalone configurations outside standard DNF/Flatpak packages.

### AB Download Manager
An open-source download manager designed to organize, accelerate, and control file downloads (uses multi-connection technology).
```bash
# Download and execute the official installation script:
bash <(curl -fsSL https://raw.githubusercontent.com/amir1376/ab-download-manager/master/scripts/install.sh)
```
> **[REFINE]**
> To complete browser integration, install the official **AB Download Manager Extension** from the Chrome Web Store or Firefox Add-ons.

### SDKman (Java & JVM tools)
A tool for managing parallel versions of multiple Software Development Kits on most Unix-based systems.
```bash
curl -s "https://get.sdkman.io" | bash
source ~/.sdkman/bin/sdkman-init.sh
sdk install java 21.0.3-tem   # Example: Install Temurin Java 21 LTS
```

### Node.js Version Manager (NVM)
A version manager for Node.js, designed to be installed per-user.
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# Open a new shell, then:
nvm install --lts && nvm use --lts
```

### JetBrains Toolbox
App manager for JetBrains IDEs to easily install, update, and manage developer applications.
```bash
# Download tar.gz from jetbrains.com, extract, and execute:
tar -xzf jetbrains-toolbox-*.tar.gz
./jetbrains-toolbox-*/jetbrains-toolbox
```

### Docker CE Engine
The official container runtime engine for enterprise developers.
```bash
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER # Run docker without sudo (requires re-login)
```
