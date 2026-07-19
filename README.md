# Reinstall Framework & OS Configurations

## About

A framework designed to help the user to safely backup and restore their setup after a fresh reinstallation of OS (Fedora KDE Plasma). I created this for my personal use, hence most of the default settings are based on my own requirements. The goal is to get your system up and running like before in no time.

I am well aware that there are existing tools to get to the same results. My intention here is to go beyond regular dotfiles to also include packages, snapper configuration, cloud sync, power profiles, and automated backup timers.

---

## Table of Contents

- [1. Key Assumptions](#1-key-assumptions)
  - [1.1 Directory Layout](#11-directory-layout)
  - [1.2 Tag Conventions](#12-tag-conventions)
  - [1.3 Permissions & Ownership Policy](#13-permissions--ownership-policy)
- [2. Partition Setup & Formatting [CAUTION, HARDWARE]](#2-partition-setup--formatting-caution-hardware)
  - [2.1 Check existing disks and free space](#21-check-existing-disks-and-free-space)
  - [2.2 Format and Label Partitions](#22-format-and-label-partitions)
  - [2.3 Temporary Mounts for Repository Setup](#23-temporary-mounts-for-repository-setup)
- [3. Set up git and clone the os-configs repository](#3-set-up-git-and-clone-the-os-configs-repository)
  - [3.1 SSH Setup](#31-ssh-setup)
  - [3.2 Authenticate GitHub CLI & Clone Repository](#32-authenticate-github-cli--clone-repository)
  - [3.3 SSH startup loading](#33-ssh-startup-loading)
- [4. Default Configuration [FIRST-TIME-BACKUP, FIRST-TIME-RESTORE]](#4-default-configuration-first-time-backup-first-time-restore)
  - [4.1 Default config variables and keys](#41-default-config-variables-and-keys)
  - [4.2 Initializing Default Configurations](#42-initializing-default-configurations)
- [5. Restore Configurations & Desktop Settings](#5-restore-configurations--desktop-settings)
- [6. Set Up BTRFS & Snapper [CAUTION, FEDORA]](#6-set-up-btrfs--snapper-caution-fedora)
  - [6.1 Initialize Post-Installation Snapshot](#61-initialize-post-installation-snapshot)
- [7. Configure Google Drive Mount (Rclone) [CAUTION]](#7-configure-google-drive-mount-rclone-caution)
  - [7.1 Configure Rclone Google Drive](#71-configure-rclone-google-drive)
- [8. Enable Automation Background Timers](#8-enable-automation-background-timers)
  - [8.1 Enable Background Timers](#81-enable-background-timers)
  - [8.2 Command Aliases for Service Management](#82-command-aliases-for-service-management)
- [9. Setting up Package Manager [FEDORA]](#9-setting-up-package-manager-fedora)
- [10. GPU Setup & Secure Boot Key Enrollment](#10-gpu-setup--secure-boot-key-enrollment)
  - [10.1 Install GPU Drivers [HARDWARE]](#101-install-gpu-drivers-hardware)
  - [10.2 Secure Boot](#102-secure-boot)
- [11. Application Installations & Customizations](#11-application-installations--customizations)
  - [11.1 Using DNF and Flatpak Packages](#111-using-dnf-and-flatpak-packages)
  - [11.2 Purging Unwanted Applications](#112-purging-unwanted-applications)
  - [11.3 Manual Installations (Third-Party Tools)](#113-manual-installations-third-party-tools)
- [12. System Verification](#12-system-verification)

---

### 1. Key Assumptions

#### 1.1 Directory Layout

```text
os-configs/
├── lib/
│   └── common.sh
├── framework/
│   ├── scripts/
│   └── configs/
├── init/
├── keys/
└── user-configs/
    ├── custom/
    │   └── bin/
    ├── home/
    └── system/
```

- **framework** - Files associated with creating and maintaining this framework
- **init** - Default templates and configurations for first-time setup
- **keys** - Sensitive information. Never commit these to Git.
- **user-configs** - User and system dotfiles
  - **custom** - User-maintained custom dotfiles
  - **home** - Dotfiles associated with the home directory
  - **system** - Dotfiles associated with the root directory (`/etc`)

ℹ️ Note: The framework will use the default directory structure and partition layout in many of the configurations, especially before cloning the repository. If you prefer custom labels and directory structures, update the commands accordingly.

#### 1.2 Tag Conventions

- `[CAUTION]`: Affects system boot partition flags, mounts, or secure states. Pay special attention when performing actions in this category.
- `[HARDWARE]`: Section is tailored for specific hardware.
- `[FEDORA]`: Section specifically associated with the Fedora KDE Plasma setup.
- `[FIRST-TIME-BACKUP]`: Section designed for the first-time backup use case.
- `[FIRST-TIME-RESTORE]`: Section associated with a first-time restore.

#### 1.3 Permissions & Ownership Policy

To maintain a secure and consistent environment, the framework enforces creation policies using a `umask 027` configuration:

- **Umask Policy**: The `umask 027` is globally configured at the top of `layout.env` (for all script operations) and `custom/.profile` (for user sessions). This automatically ensures that any new directory is created with `750` permissions and any new file is created with `640` permissions.
- **System Configurations**: System files and directories restored under `/etc/` are set to default permissions (directories: `750`, files: `640`) and owned by `root:root`.

---

### 2. Partition Setup & Formatting [CAUTION, HARDWARE]

Format the disk and create partitions depending on the number and size of disks. The goal is to create three partitions (ext4) with labels `core`, `library`, and `temp`. If you only formatted your root partition during install and your other data partitions exist, skip this step. It is **recommended** to use a GUI like `KDE Partition Manager`.

ℹ️ Note: If you choose not to create partitions or use different labels/directory names, update `framework/configs/layout.env` accordingly once you clone the repository.

#### 2.1 Check existing disks and free space

Get the details about your disk and current usage. Use these commands in subsequent steps to validate.

```shell
lsblk -o UUID,MODEL,NAME,LABEL,SIZE,FSTYPE,MOUNTPOINT
sudo parted /dev/sda unit GB print free
```

#### 2.2 Format and Label Partitions

Update the variables as per your disk and requirements. You can skip this step if you have already formatted or don't want to create separate partitions. Unmount any existing partitions using `sudo umount <path>` before re-partitioning.

Define shared variables (customize disk and size values as needed). Leave some extra space at the end for SSD **over-provisioning**. The expected unit is GiB. Replace `/dev/sda` with your target disk.

```shell
DISK="/dev/sda"

PARTITION_LABEL1="core"
PARTITION_SIZE1=200

PARTITION_LABEL2="library"
PARTITION_SIZE2=600

PARTITION_LABEL3="temp"
PARTITION_SIZE3=100
```

#### Scenario 1 - Wipe existing disk and create partitions

⚠️ Warning: This will wipe out the entire disk. Backup any data before proceeding.

```shell
sudo parted -s $DISK mklabel gpt
PARTITION_START_OFFSET1=0
FIRST_PART_NUM=1
```

#### Scenario 2 - Shrink the existing root partition and create partitions in freed space

This assumes you want to shrink an existing root partition (by default assumed to be partition 2 on UEFI setups, or partition 1 on legacy setups). Set `SHRINK_TO_SIZE` to the target size (in GiB) you want to shrink it down to. The script validates that this value is not larger than the current disk size and leaves enough room for all three new partitions.

```shell
SHRINK_TO_SIZE=200

DISK_SIZE=$(( $(lsblk -b -d -n -o SIZE "$DISK") / 1024 / 1024 / 1024 ))
MIN_REQUIRED_GiB=$((PARTITION_SIZE1 + PARTITION_SIZE2 + PARTITION_SIZE3))

if (( SHRINK_TO_SIZE >= DISK_SIZE )); then
    echo "SHRINK_TO_SIZE (${SHRINK_TO_SIZE} GiB) must be less than disk size (${DISK_SIZE} GiB)"
elif (( DISK_SIZE - SHRINK_TO_SIZE < MIN_REQUIRED_GiB )); then
    echo "Not enough free space after shrink. Need ${MIN_REQUIRED_GiB} GiB, only $((DISK_SIZE - SHRINK_TO_SIZE)) GiB available."
else
    if [[ "$DISK" =~ [0-9]$ ]]; then
        PART_PREFIX="${DISK}p"
    else
        PART_PREFIX="$DISK"
    fi
    # Set this to the root partition number (e.g., 2 on UEFI setups, 1 on legacy/non-UEFI)
    ROOT_PART_NUM=2
    ROOT_PART="${PART_PREFIX}${ROOT_PART_NUM}"
    sudo e2fsck -f -y "$ROOT_PART"
    sudo resize2fs "$ROOT_PART" "${SHRINK_TO_SIZE}G"
    sudo parted -s "$DISK" unit GiB resizepart "${ROOT_PART_NUM}" "${SHRINK_TO_SIZE}"
    PARTITION_START_OFFSET1=$SHRINK_TO_SIZE
    FIRST_PART_NUM=$((ROOT_PART_NUM + 1))
fi
```

**Create partitions** (run after either scenario above)

```shell
PARTITION_START_OFFSET2=$((PARTITION_START_OFFSET1 + PARTITION_SIZE1))
PARTITION_START_OFFSET3=$((PARTITION_START_OFFSET2 + PARTITION_SIZE2))

sudo parted -a optimal -s $DISK mkpart $PARTITION_LABEL1 "${PARTITION_START_OFFSET1}GiB" "${PARTITION_START_OFFSET2}GiB"
sudo parted -a optimal -s $DISK mkpart $PARTITION_LABEL2 "${PARTITION_START_OFFSET2}GiB" "${PARTITION_START_OFFSET3}GiB"
sudo parted -a optimal -s $DISK mkpart $PARTITION_LABEL3 "${PARTITION_START_OFFSET3}GiB" "100%"
```

**Format the new partitions** (run after either scenario above)

```shell
if [[ "$DISK" =~ [0-9]$ ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="$DISK"
fi

sudo udevadm settle
sudo mkfs.ext4 -L $PARTITION_LABEL1 "${PART_PREFIX}${FIRST_PART_NUM}"
sudo mkfs.ext4 -L $PARTITION_LABEL2 "${PART_PREFIX}$((FIRST_PART_NUM + 1))"
sudo mkfs.ext4 -L $PARTITION_LABEL3 "${PART_PREFIX}$((FIRST_PART_NUM + 2))"
```

ℹ️ Note: For any other scenario, use a GUI tool like `KDE Partition Manager` as recommended at the start of this section.

#### 2.3 Temporary Mounts for Repository Setup

To clone the repository and run the setup scripts, temporarily mount the `core` partition. We will later update `/etc/fstab` to ensure that partitions are loaded at startup:

```shell
sudo mkdir -p /mnt/core
sudo mount LABEL=core /mnt/core
sudo chown -R $USER:$USER /mnt/core
```

ℹ️ Note: Throughout the rest of this guide, the cloned repository path `/mnt/core/os-configs` is assumed as the base directory for all operations and configuration scripts.

---

### 3. Set up git and clone the os-configs repository

Install the bare minimum bootstrap tools needed to authenticate, configure snapper, and clone files (the remaining system-required packages will be installed during Section 11):

```shell
sudo dnf install -y --skip-unavailable crudini git gh ksshaskpass 7zip rclone snapper rsync
```

#### 3.1 SSH Setup

- **Scenario A - Restoring existing keys**: If the keys already exist in the default `keys/.ssh/` directory or any other custom location:

```shell
install -D -t ~/.ssh/ /mnt/core/os-configs/keys/.ssh/id_ed25519* && chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub
```

- **Scenario B - [FIRST-TIME-RESTORE]**: If you don't have your original ssh keys or never configured any, create a new ssh key. The ssh key title will be username@hostname. Enter the passphrase and save it for future reference.

```shell
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
```

After creating (or copying) the key, update permissions to restrict access to the current user only.

```shell
chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub
```

ℹ️ SSH Permissions Policy:

- The SSH configuration folder `~/.ssh` is restricted to `700`.
- The private key (`~/.ssh/id_ed25519`) is restricted to `600`.
- The public key (`~/.ssh/id_ed25519.pub`) is set to `644`.

Start the agent if not running. If no key is loaded, add the key:

```shell
ssh-add -l
SSH_STATUS=$?
if [[ $SSH_STATUS -eq 2 ]]; then
    eval $(ssh-agent)
fi
if [[ $SSH_STATUS -gt 0 ]]; then
    ssh-add ~/.ssh/id_ed25519
fi
ssh-add -l
echo $SSH_AUTH_SOCK
```

We will later configure the ssh to auto-load at startup without having to enter passphrase every time.

#### 3.2 Authenticate GitHub CLI & Clone Repository

Login to github using gh cli auth command. When prompted select **SSH** as the mode of communication and then select the key to upload to github. Your ssh public key will be automatically added to your account.

```shell
gh auth login
ssh -T git@github.com
gh auth status
```

Clone the repository os-configs

```shell
gh repo clone <github-username>/os-configs /mnt/core/os-configs
```

#### 3.3 SSH startup loading

Registers SSH key with KDE Wallet for passwordless unlock on login.

ℹ️ Note: The ssh autostart script is stored inside the `user-configs/custom` directory and will be automatically deployed when home configurations are restored in **Section 5**. No manual copying or permissions setup is required during this step.

To register your password with `ksshaskpass` now (select "Remember password" in the popup):

```shell
SSH_ASKPASS_REQUIRE=prefer ssh-add ~/.ssh/id_ed25519
```

---

### 4. Default Configuration [FIRST-TIME-BACKUP, FIRST-TIME-RESTORE]

If you are using this framework for the first time, you may not have any customized configs. The framework provides some default templates for the configs to get you started.

#### 4.1 Default config variables and keys

- The `keys/` directory contains local security credentials and environment identities. It is ignored by Git in `.gitignore` and **must never** be committed or pushed to public repositories.

- If you already have a stored `keys/` directory elsewhere, restore its contents into the `keys/` directory in the repository. Otherwise, copy the template `init/configs/identity.env.default` file into the keys folder, fill in the details, and rename the file to `identity.env`. You can copy and rename the template file using:

    ```shell
    install -D /mnt/core/os-configs/init/configs/identity.env.default /mnt/core/os-configs/keys/identity.env
    ```

- The live `framework/configs/layout.env` file contains environment variables pointing to directories and files.

- Once your configurations and mount points are updated in `layout.env`, run the fstab automation script with `sudo` to create directories, set correct ownership and permissions (750), and finalize entries in `/etc/fstab`:

    ```shell
    sudo /mnt/core/os-configs/framework/scripts/update-fstab.sh
    ```

- To load the identity keys and sensitive environment variables, source the `identity.env` file in your shell or script:

    ```shell
    source /mnt/core/os-configs/keys/identity.env
    ```

The primary SSH key for Git communication is now configured. If you have additional SSH keys in your live SSH directory, copy them to the keys vault using:

```shell
install -D -t /mnt/core/os-configs/keys/.ssh/ ~/.ssh/id_ed25519*
```

#### 4.2 Initializing Default Configurations

The `init` directory contains clean, default configuration templates for system configurations and core apps. If you do not have existing configurations to restore, you can generate default templates:

```shell
cd /mnt/core/os-configs && bash init/scripts/init-defaults.sh --all
```

Alternative flags for the initialization script:

- `--all` (Default): Generates all default configuration profiles.
- `--git`: Generates `user-configs/home/.gitconfig`.
- `--ssh`: Generates `user-configs/home/.ssh/config`.
- `--profile`: Generates `user-configs/custom/.profile`.
- `--dnf`: Generates `user-configs/system/dnf/dnf.conf`.
- `--snapper`: Generates `user-configs/system/snapper/configs/root`.
- `--power`: Generates `user-configs/home/.config/powerdevilrc`.
- `--identity`: Generates `keys/identity.env`.

---

### 5. Restore Configurations & Desktop Settings

The restoration script parses `restore.conf` and copies configuration profiles to their relative home and system locations (including SSH configurations, KDE Powerdevil profiles, and DNF configs). You can selectively restore components using command-line flags:

- `--all` (Default): Restores both system configurations and private keys (gitconfig, SSH).
- `--configs`: Restores only system and user configurations matching `restore.conf`.
- `--keys`: Restores only private credentials and keypairs from the local vault.
- `-f` or `--force`: Force-restores conflicting files (where the repository and live versions differ), backing up the existing live copy to `backup/live/` (preserving directory structure) before overwriting. Without this flag, any conflicting file is safely skipped.

```shell
bash /mnt/core/os-configs/framework/scripts/restore-configs.sh --all [-f | --force]
```

---

### 6. Set Up BTRFS & Snapper [CAUTION, FEDORA]

The Snapper setup script generates root snapshot rules, optimizes timeline retention limits, and configures GRUB boot submenus. For detailed setup and configuration details, see the [Snapper Arch Wiki](https://wiki.archlinux.org/title/Snapper).

ℹ️ Note: Running the Snapper setup script requires `sudo` privileges because it configures system-wide Btrfs subvolumes, registers Snapper configs, and updates the GRUB boot menu. If the Snapper root configuration template is missing from both `/etc/snapper/configs/root` and the repository backups, the script will exit with an error instructing you to run `restore-configs.sh` or `init-defaults.sh` first.

```shell
sudo bash /mnt/core/os-configs/framework/scripts/snapper-setup.sh
```

The script performs the following actions:

- Checks for snapper root configurations (throws an error if missing).
- Ensures that the snapshot subvolume (`/.snapshots`) is BTRFS. If not, deletes and creates a new subvolume.
- Enables snapper cleanup timers.
- Ensures `grub-btrfs` is installed and enables the `grub-btrfsd` daemon service.
- Configures GRUB menu visibility and timeouts.
- Regenerates the GRUB config targeting `/boot/grub2/grub.cfg`.

#### 6.1 Initialize Post-Installation Snapshot

Take a snapshot immediately to capture the baseline state, and verify that it has been registered:

```shell
sudo snapper -c root create -d "Post OS Installation"
sudo snapper -c root list
```

---

### 7. Configure Google Drive Mount (Rclone) [CAUTION]

#### 7.1 Configure Rclone Google Drive

If this is your first time configuring Rclone, refer to the official [Rclone Installation Guide](https://rclone.org/install/) and the [Rclone Google Drive Setup Guide](https://rclone.org/drive/) for step-by-step instructions.

Configure rclone Google Drive credentials and mount parameters:

```shell
rclone config
```

ℹ️ Note: Sensitive credentials, OAuth Client IDs, and Access tokens reside inside `~/.config/rclone/rclone.conf` which is backed up.

Add the rclone mount configuration to fstab:

```shell
sudo bash /mnt/core/os-configs/framework/scripts/rclone-setup.sh
```

---

### 8. Enable Automation Background Timers

The background automation framework is built around three distinct operations:

1. **Backup**: Pulls/syncs the latest live files (home configurations, system files, and private keys) from the active running system into your local `os-configs` repository directory (`backup-configs.sh`). By default, conflicting files (differing between live and repository) are skipped. Run with `-f` or `--force` to overwrite the repository copies, which automatically backs up the existing repository files to `backup/repo/` (preserving directory structure) first.
2. **Git Commit & Push**: Commits the updated files in the local repository and pushes them to your GitHub remote repository (`git-autopush.sh`).
3. **GDrive Sync**: Compresses the local repository folder (excluding `.git/`, `keys/`, and the local `backup/` folders) and updates the archive on your Google Drive mount (`gdrive-backup.sh`).

#### 8.1 Enable Background Timers

Once your configuration files are restored and your shell environment is reloaded (which registers the custom command aliases), you can easily activate the background timers. Both timers automatically run the **Backup** operation first to capture the latest live system changes before performing their respective upload/push task:

- **Sync Automation (Backup + Git Commit & Push)**: Activate the weekly Git synchronization timer.
  
  ```shell
  os-configs-sync-enable
  ```

- **Cloud Backup Automation (Backup + GDrive Sync)**: Activate the weekly Google Drive backup timer.
  
  ```shell
  os-configs-gdrive-enable
  ```

#### 8.2 Command Aliases for Service Management

ℹ️ Note: Sourcing the custom profile script (`custom/.profile`) automatically registers convenient Git synchronization and Google Drive backup aliases directly to your shell environment:

| Category | Alias | Description | Equivalent systemd Command |
| :--- | :--- | :--- | :--- |
| Git Sync | `os-configs-sync-now` | Force-start local files backup and Git push immediately | `systemctl --user start os-configs-sync.service` |
| Git Sync | `os-configs-sync-enable` | Enable and start the weekly Git synchronization timer | `systemctl --user enable --now os-configs-sync.timer` |
| Git Sync | `os-configs-sync-disable` | Disable and stop the weekly Git synchronization timer | `systemctl --user disable --now os-configs-sync.timer` |
| Git Sync | `os-configs-sync-logs` | View the last 20 log messages for the Git sync service | `journalctl --user -u os-configs-sync.service -n 20` |
| GDrive | `os-configs-gdrive-now` | Compress local files and update Google Drive archive immediately | `systemctl --user start os-configs-gdrive.service` |
| GDrive | `os-configs-gdrive-enable` | Enable and start the weekly Google Drive backup timer | `systemctl --user enable --now os-configs-gdrive.timer` |
| GDrive | `os-configs-gdrive-disable` | Disable and stop the weekly Google Drive backup timer | `systemctl --user disable --now os-configs-gdrive.timer` |
| GDrive | `os-configs-gdrive-logs` | View the last 20 log messages for the GDrive backup service | `journalctl --user -u os-configs-gdrive.service -n 20` |
| General | `os-configs-status` | List all active timers, their next run schedules, and remaining time | `systemctl --user list-timers "os-configs-*"` |

Reboot: **PERFORM REBOOT (Verifies Bootloader Menu, Snapshots, and Active Services)**

---

### 9. Setting up Package Manager [FEDORA]

The package manager setup script updates system packages, deploys optimized DNF settings, and enables RPM Fusion and Terra repositories:

```shell
sudo bash /mnt/core/os-configs/framework/scripts/dnf-setup.sh
```

---

### 10. GPU Setup & Secure Boot Key Enrollment

#### 10.1 Install GPU Drivers [HARDWARE]

Check your GPU:

```shell
lspci | grep -E -i "vga|3d|display"
```

**AMD (iGPU):** mesa/RADV drivers run natively. Verify output of:

```shell
glxinfo | grep "OpenGL renderer"
```

**NVIDIA (dGPU):** Install drivers:

```shell
sudo dnf install akmod-nvidia
```

#### 10.2 Secure Boot

To check if secure boot is enabled or not use:

```shell
mokutil --sb-state
```

The secure boot can be disabled permanently from UEFI firmware screen. You can also disable it using:

```shell
sudo mokutil --disable-validation
```

If Secure Boot is enabled in your BIOS, you must enroll your signature key to allow the NVIDIA driver to load. For detailed registration steps, see the [Fedora Wiki Secure Boot](https://fedoraproject.org/wiki/Secureboot) and the [RPM Fusion Secure Boot Guide](https://rpmfusion.org/Howto/Secure%20Boot).

```shell
sudo kmodgenca -a
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

Enter a temporary password when prompted.

⚠️ [CAUTION] DO NOT SKIP THE BLUE MOK SCREEN ON REBOOT!

1. When the laptop restarts, it will show a blue screen titled "Shim UEFI key management" or "MOK Manager".
2. You must select "Enroll MOK" -> "Continue" -> "Yes" -> enter the temporary password you defined above.
3. Select "Reboot" to finish.

⚠️ If you skip this blue screen or hit any key to continue default boot, the kernel will refuse to load the unsigned NVIDIA driver on boot, locking you at a black boot-loop screen.

Reboot: **PERFORM REBOOT (Enrolls Secure Boot Keys & Loads GPU Kernel Modules)**

Rebuild the nvidia drivers:

```shell
sudo akmods --force --rebuild
```

---

### 11. Application Installations & Customizations

#### 11.1 Using DNF and Flatpak Packages

The package installation script installs DNF packages, Flatpaks, and configures sandboxed permissions overrides:

```shell
sudo bash /mnt/core/os-configs/framework/scripts/install-packages.sh --daily
```

Alternative flags for the package installation script:

- `--required`: Installs only core required utilities (git, gh, rclone, crudini, switcheroo, etc.).
- `--daily` (Default): Installs core required utilities and daily-driver applications (web browser, office suite, media players, etc.).
- `--dev`: Installs core required utilities and development tools (like VS Code, DBeaver, MongoDB Compass).
- `--all`: Installs all categories combined (required, daily-driver, and development).

#### 11.2 Purging Unwanted Applications

Validate and remove listed default games, Akonadi organizers, and other unwanted applications to clean the system:

```shell
sudo bash /mnt/core/os-configs/framework/scripts/uninstall-unwanted.sh
```

#### 11.3 Manual Installations (Third-Party Tools)

These applications require manual scripts, external tarballs, or standalone configurations outside standard DNF/Flatpak packages.

##### AB Download Manager

An open-source download manager designed to organize, accelerate, and control file downloads.

```shell
bash <(curl -fsSL https://raw.githubusercontent.com/amir1376/ab-download-manager/master/scripts/install.sh)
```

ℹ️ Note: To complete browser integration, install the official AB Download Manager Extension from the Chrome Web Store or Firefox Add-ons.

##### SDKman (Java & JVM tools)

A tool for managing parallel versions of multiple Software Development Kits on most Unix-based systems.

```shell
curl -s "https://get.sdkman.io" | bash
source ~/.sdkman/bin/sdkman-init.sh
sdk install java 21.0.3-tem
```

##### Node.js Version Manager (NVM)

A version manager for Node.js, designed to be installed per-user.

```shell
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
nvm install --lts && nvm use --lts
```

##### JetBrains Toolbox

App manager for JetBrains IDEs to easily install, update, and manage developer applications.

```shell
tar -xzf jetbrains-toolbox-*.tar.gz
./jetbrains-toolbox-*/jetbrains-toolbox
```

##### Docker CE Engine

The official container runtime engine for enterprise developers.

```shell
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

---

### 12. System Verification

Check system integrity and verify that all configurations are correct, all requested applications mentioned in the configuration files are installed, and all unwanted applications have been successfully removed:

ℹ️ Note: Running the verification script requires `sudo` privileges to validate Snapper rules, check system-wide GRUB parameters, and inspect block mounts.

```shell
sudo bash /mnt/core/os-configs/framework/scripts/verify-setup.sh
```
