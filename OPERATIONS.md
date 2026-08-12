# Operations Reference Guide

## About

This document provides a quick reference of essential commands for managing the OS, configurations, backups, and applications.

## Table of Contents

- [1. Apps and Utilities](#1-apps-and-utilities)
- [2. Snapper](#2-snapper)
- [3. Backup Related Commands](#3-backup-related-commands)
  - [3.1 Command Aliases](#31-command-aliases)
  - [3.2 Customizing Background Timers](#32-customizing-background-timers)
  - [3.3 Backup Script](#33-backup-script)
  - [3.4 Restore Script](#34-restore-script)
  - [3.5 Execution Ordering Rules](#35-execution-ordering-rules)
  - [3.6 Manual Git and GDrive Sync](#36-manual-git-and-gdrive-sync)
  - [3.7 Configuration Maintenance](#37-configuration-maintenance)
  - [3.8 Keys Vault](#38-keys-vault)
- [4. Rclone](#4-rclone)
- [5. System Diagnostics](#5-system-diagnostics)
  - [5.1 Hardware Status (Temps, Fans, Frequency, Power)](#51-hardware-status-temps-fans-frequency-power)
  - [5.2 Process and Resource Usage](#52-process-and-resource-usage)
  - [5.3 Disk Usage](#53-disk-usage)
  - [5.4 System Logs (Journalctl)](#54-system-logs-journalctl)
- [6. Advanced GPU and CPU configuration](#6-advanced-gpu-and-cpu-configuration)
  - [6.1 GPU Switching and Offloading](#61-gpu-switching-and-offloading)
  - [6.2 Power Profiles and CPU Scaling](#62-power-profiles-and-cpu-scaling)
  - [6.3 NVIDIA GPU Specific Configuration](#63-nvidia-gpu-specific-configuration)
- [7. Firmware](#7-firmware)
  - [7.1 Firmware Management](#71-firmware-management)
- [8. Package Management](#8-package-management)
  - [8.1 Basic Package Management](#81-basic-package-management)
  - [8.2 Search & Inspect](#82-search--inspect)
  - [8.3 System Audits & File Ownership Queries](#83-system-audits--file-ownership-queries)
  - [8.4 Flatpak Permissions & Overrides](#84-flatpak-permissions--overrides)
  - [8.5 DNF Transaction History](#85-dnf-transaction-history)

---

### 1. Apps and Utilities

Below is a summary of the key tools and utilities referenced in this guide:

| Tool | Description |
| :--- | :--- |
| `snapper` | Btrfs snapshot creation, deletion, and management tool. |
| `btrfs` | Administrative utility for Btrfs filesystems to manage space and check disk usage. |
| `rclone` | Command-line program to synchronize files and directories to and from Google Drive cloud storage. |
| `pgrep` | Command-line utility to search for active processes by name. |
| `systemctl` | Systemd utility to query and control the state of system services and mounts. |
| `fwupdmgr` | Command-line client for the fwupd daemon to refresh and update system firmware. |
| `sensors` | Hardware monitoring tool (lm_sensors) for real-time temperatures, voltages, and fan speeds. |
| `watch` | Tool to run commands periodically and view outputs in real-time. |
| `cpupower` | Tool to view and configure processor power states and governor settings. |
| `powertop` | Power consumption diagnosis and optimization tool. |
| `nvtop` | Ncurses-based real-time GPU process monitor for AMD and NVIDIA GPUs. |
| `nvidia-smi` | NVIDIA System Management Interface utility to monitor and configure NVIDIA GPUs. |
| `radeontop` | Interactive tool to monitor AMD Radeon GPU utilization. |
| `powerprofilesctl` | Query and switch active system power profiles. |
| `ps` | Utility to report snapshots of current processes. |
| `lsof` | Tool to list open files and network connections. |
| `du` | Estimate file and directory space usage. |
| `ncdu` | Interactive ncurses-based disk usage analyzer. |
| `journalctl` | Systemd utility to query and view diagnostic logs. |

---

### 2. Snapper

| Command | Description |
| :--- | :--- |
| `sudo snapper -c root get-config` | Check the settings of the Snapper root configuration. |
| `sudo snapper -c root list` | View the list of current snapper snapshots. |
| `sudo snapper -c root create --description "Manual snapshot before doing important work" --cleanup-algorithm number` | Create a manual read-only snapshot prior to performing system maintenance or upgrades. |
| `sudo snapper -c root delete <snapshot_number>` | Delete a manual snapshot after verifying system stability. |
| `sudo snapper rollback` | Restore snapshots via GRUB: Run the rollback command from within a booted snapshot to make it permanent. |
| `sudo snapper -c root rollback <snapshot_number>` | Perform a manual rollback to a specific snapshot state directly from the command line. |
| `sudo btrfs filesystem du -s /.snapshots/` | Show the disk space usage of the snapper snapshots. |
| `sudo btrfs filesystem usage /` | View overall filesystem space details. |

---

### 3. Backup Related Commands

#### 3.1 Command Aliases

These aliases are registered automatically in the shell environment via `user-configs/custom/.profile` for systemd service and timer management:

| Alias | Description |
| :--- | :--- |
| `os-configs-status` | List all active user timers, their next run schedules, and remaining time. |
| `os-configs-sync-now` | Force-start local files backup and Git push immediately. |
| `os-configs-sync-enable` | Enable and start the weekly Git synchronization timer. |
| `os-configs-sync-disable` | Disable and stop the weekly Git synchronization timer. |
| `os-configs-sync-logs` | View the last 20 log messages for the Git sync service. |
| `os-configs-gdrive-now` | Synchronize local configurations, compress them, and update Google Drive archive immediately. |
| `os-configs-gdrive-enable` | Enable and start the weekly Google Drive backup timer. |
| `os-configs-gdrive-disable` | Disable and stop the weekly Google Drive backup timer. |
| `os-configs-gdrive-logs` | View the last 20 log messages for the Google Drive backup service. |

#### 3.2 Customizing Background Timers

By default, systemd timers are configured to trigger weekly. If you want to change the frequency (e.g., from weekly to daily or to a specific hour):

1. Edit the timer files directly in the repository (e.g., `user-configs/home/.config/systemd/user/os-configs-sync.timer` for Git push sync, or `user-configs/home/.config/systemd/user/os-configs-gdrive.timer` for Google Drive sync).

2. Change the `OnCalendar` parameter under the `[Timer]` section (for example, set `OnCalendar=daily` to run daily at midnight, or `OnCalendar=*-*-* 12:00:00` to run daily at 12:00 PM).

3. Deploy the updated timer files using the restore script, and then reload the systemd daemon to apply the changes:

   ```shell
   systemctl --user daemon-reload
   ```

Alternatively, you can create systemd overrides directly using:

```shell
systemctl --user edit os-configs-sync.timer
systemctl --user edit os-configs-gdrive.timer
```

#### 3.3 Backup Script

Run the backup script directly to copy configurations from your live system to the repository directory:

```shell
user-configs/custom/bin/backup-configs.sh [-f | --force]
```

- **Default:** Copies live files that are **newer** than the repository copy. The old repository copy is always backed up to `backup/repo/` first (backup log). If the repository copy is **newer** than the live file (conflict), the file is skipped and logged.
- **Force (`-f` or `--force`):** Also overwrites conflicts (repo newer than live), backing them up to `backup/repo/` first (conflict log).
- **Repository Pruning:** Removes untracked files in the repository no longer listed in `sync-manifest.conf`, saving them to `backup/repo/` first.

#### 3.4 Restore Script

Run the restore script directly to copy configuration templates from the repository to the live system:

```shell
bash framework/scripts/restore-configs.sh --configs [-f | --force]
```

- **Default:** Copies repository files that are **newer** than the live copy. The old live copy is always backed up to `backup/live/` first (backup log). If the live copy is **newer** than the repository file (conflict), the file is skipped and logged.
- **Force (`-f` or `--force`):** Also overwrites conflicts (live newer than repo), backing them up to `backup/live/` first (conflict log).

#### 3.5 Execution Ordering Rules

Running the backup and restore operations in sequence has specific outcomes depending on which script is executed first:

- **Conflict definition:** A file is a conflict when the **destination** is newer than the source. Force is required to overwrite a conflict.
- **Non-conflict overwrite:** When the source is newer, the file is always copied (no force needed) and the destination is backed up first.
- **No-Force Ordering:** Running backup then restore (or vice versa) without `--force` — non-conflicting files are synced by the first script. The second script then has nothing to do for those files. True conflicts are safely skipped by both.
- **Force Ordering:** Running either script with `--force` first aligns the live and repository states. The second script becomes a no-op.
- **Backup Archives:** Files saved to `backup/live/` or `backup/repo/` are overwritten on the next run if the same file is backed up again. Review and merge any important differences before re-running.

#### 3.6 Manual Git and GDrive Sync

Instead of waiting for the weekly background timers, you can use the custom command aliases to run manual syncs and pushes immediately:

**Manual Git Sync** — Force-start the local file backup and push to GitHub immediately:

```shell
os-configs-sync-now
```

**Manual GDrive Sync** — Compress the local files and update the Google Drive archive immediately:

```shell
os-configs-gdrive-now
```

**Raw Script Execution** — Alternatively, you can run the raw scripts directly if needed:

- **Git Autopush:** `user-configs/custom/bin/git-autopush.sh`
- **GDrive Backup:** `user-configs/custom/bin/gdrive-backup.sh`

#### 3.7 Configuration Maintenance

To maintain configurations correctly, updates must be handled at the proper levels:

**System Verification** — Before running any backup script, it is highly recommended to run the verification script to check which files currently differ between your live system and the repository:

```shell
sudo bash framework/scripts/verify-setup.sh
```

**Custom Configurations (`user-configs/custom/`)** — These are user-maintained scripts and custom configurations (e.g., custom aliases, profiles). They are always maintained at the repository level and should be edited inside the repository directory (`user-configs/custom/`), not in the live home folder.

**Sync Manifest (`framework/configs/sync-manifest.conf`)** — This is the master list of tracked files. If you want to add new configurations to be backed up or remove old ones from tracking, edit this file at the repository level.

**Packages Configuration (`framework/configs/packages.conf`)** — This is the master list of packages to install or uninstall. If you want to add or remove packages from your system configuration, edit this file at the repository level.

**All Other Configurations (Home & System)** — Any other files (such as `.bashrc`, `.config/powerdevilrc`, or system files under `/etc/`) must be updated at their real live paths (e.g., in your home directory or `/etc/`) and **not** inside the repository directory. Once updated on the live system, run the backup script to sync them into the repository.

#### 3.8 Keys Vault

The `keys/` directory is excluded from all automated Git and Google Drive backups by design. `keys-vault.sh` provides a manual, encrypted backup of `keys/` to Google Drive (`/mnt/core/gdrive/backup/security/` by default) using AES-256 encryption. Vault files are self-contained and portable — each includes a plaintext hint visible without decryption.

**Backup** — encrypts `keys/` and writes a timestamped vault to Google Drive:

```shell
user-configs/custom/bin/keys-vault.sh --backup --hint <text>
```

**Restore** — decrypts a specific vault back to `keys/`:

```shell
user-configs/custom/bin/keys-vault.sh --restore --src <path/to/vault.vault>
```

Key behaviours:

- The hint is displayed **before** the password prompt on restore — no password needed to see it.
- **No overwrite on either side** — backup quits if the vault file already exists; restore quits if `keys/` already exists at the destination. Remove the target manually first if needed.
- Default backup destination: `/mnt/core/gdrive/backup/security/keys-TIMESTAMP.vault`
- Default restore destination: `/mnt/core/os-configs/keys/`
- Run the script with no arguments to print all available flags and current defaults.

---

### 4. Rclone

| Command | Description |
| :--- | :--- |
| `rclone bisync gdrive: /mnt/core/gdrive --resync --resync-mode path1 --dry-run -P` | Perform a dry-run check of a manual bi-directional synchronization between Google Drive and the local directory. |
| `rclone bisync gdrive: /mnt/core/gdrive --resync --resync-mode path1 -P` | Execute a manual bi-directional synchronization between Google Drive and the local directory. |
| `rclone sync /mnt/core/gdrive gdrive: -P` | Perform manual one-way sync from local `/mnt/core/gdrive` to Google Drive remote. |
| `pgrep -a rclone` | Verify if any active Rclone synchronization or mount process is currently running. |
| `systemctl status mnt-core-gdrive.mount` | Inspect systemd status for the dynamically managed Google Drive mount point. |

---

### 5. System Diagnostics

#### 5.1 Hardware Status (Temps, Fans, Frequency, Power)

| Command | Description |
| :--- | :--- |
| `sensors` | CPU/board temps, fan speeds, voltages. |
| `watch -n1 "grep 'MHz' /proc/cpuinfo"` | Live per-core CPU frequency. |
| `cpupower frequency-info` | Current governor, min/max supported CPU frequency. |
| `sudo powertop` | Live CPU power draw and wakeups. |
| `nvtop` | Live GPU (NVIDIA + AMD) usage, temp, memory, power. |
| `nvidia-smi -q -d TEMPERATURE,CLOCK,POWER,VOLTAGE` | NVIDIA temp/clock/power/voltage details. |
| `sudo radeontop` | AMD iGPU usage/clock (live). |

#### 5.2 Process and Resource Usage

| Command | Description |
| :--- | :--- |
| `ps -p <pid> -o pid,comm,%cpu,%mem,etime` | Basic process info. |
| `lsof -p <pid>` | Files opened by a process. |
| `sudo lsof -i -a -p <pid>` | Network connections for a process. |
| `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv` | GPU usage per process (NVIDIA). |
| `htop` | Live system-wide CPU/RAM usage. |
| `ps -C <app-name> -o pid,%cpu,%mem,cmd` | CPU/RAM usage of a specific app. |
| `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv` \| `grep <app-name>` | GPU usage of a specific app. |

#### 5.3 Disk Usage

| Command | Description |
| :--- | :--- |
| `du -sh <path>` | Total size of a file or folder. |
| `du -h --max-depth=1 <path>` | Size broken down one level deep. |
| `ncdu <path>` | Interactive nested disk usage browser. |

#### 5.4 System Logs (Journalctl)

| Command | Description |
| :--- | :--- |
| `journalctl -p err -b` | Errors since last boot. |
| `journalctl -xe` | Recent logs with explanations. |
| `journalctl -f` | Follow logs live. |
| `journalctl --disk-usage` | Total space used by the journal. |

---

### 6. Advanced GPU and CPU configuration

#### 6.1 GPU Switching and Offloading

| Command | Description |
| :--- | :--- |
| `nvidia-run <command>` | Launch an application using the discrete NVIDIA GPU (`__NV_PRIME_RENDER_OFFLOAD=1`). |
| `amd-run <command>` | Launch an application using the integrated AMD GPU (`DRI_PRIME=0`). |
| `DRI_PRIME=1 <command>` | Force a command onto the discrete GPU via Mesa/Zink offload. |

#### 6.2 Power Profiles and CPU Scaling

| Command | Description |
| :--- | :--- |
| `powerprofilesctl list` | List available power profiles. |
| `powerprofilesctl set <power-saver` \| `balanced` \| `performance>` | Switch active power profile. |
| `sudo cpupower frequency-set -g <governor>` | Set CPU scaling governor. |
| `sudo cpupower frequency-set -d <min> -u <max>` | Set CPU min/max frequency (e.g. `-d 800MHz -u 4200MHz`). |

#### 6.3 NVIDIA GPU Specific Configuration

| Command | Description |
| :--- | :--- |
| `sudo nvidia-smi -lgc <min,max>` | Lock NVIDIA GPU clock to a min,max range. |
| `sudo nvidia-smi -rgc` | Reset NVIDIA GPU clock to default. |
| `sudo nvidia-smi -pl <watts>` | Set NVIDIA GPU power limit. |

---

### 7. Firmware

#### 7.1 Firmware Management

| Command | Description |
| :--- | :--- |
| `fwupdmgr refresh` | Refresh firmware metadata. |
| `fwupdmgr get-devices` | List devices with firmware info. |
| `fwupdmgr get-updates` | Check for available firmware updates. |
| `fwupdmgr update` | Apply available firmware updates. |

---

### 8. Package Management

#### 8.1 Basic Package Management

**Important:** Avoid defaulting to the `-y` auto-accept flag (e.g., `dnf install -y` or `dnf remove -y`). Reviewing the transaction plan helps prevent the accidental removal or modification of critical system dependencies.

| Operation | DNF (System) | RPM (Local Packages) | Flatpak (Sandboxed App) |
| :--- | :--- | :--- | :--- |
| **Update Repos** | `sudo dnf check-update` | — | `flatpak update --appstream` |
| **Install** | `sudo dnf install <pkg>` | `sudo rpm -i <file.rpm>` | `flatpak install <remote> <app_id>` |
| **Upgrade** | `sudo dnf upgrade` | `sudo rpm -U <file.rpm>` | `flatpak update` |
| **Remove** | `sudo dnf remove <pkg>` | `sudo rpm -e <pkg>` | `flatpak uninstall <app_id>` |
| **Autoremove** | `sudo dnf autoremove` | — | `flatpak uninstall --unused` |
| **Clean Cache** | `sudo dnf clean all` | — | — |
| **Reinstall** | `sudo dnf reinstall <pkg>` | — | `flatpak install --reinstall <remote> <app_id>` |
| **Downgrade** | `sudo dnf downgrade <pkg>` | `sudo rpm -U --oldpackage <file.rpm>` | `flatpak update --commit=<hash> <app_id>` |

#### 8.2 Search & Inspect

Use these commands when the exact package name is unknown, or to show descriptions and sizes before modifying files.

| Command | Description |
| :--- | :--- |
| `dnf search <query>` | Search DNF package names and summaries. |
| `dnf info <pkg>` | Show detailed description, size, and version to verify a package before action. |
| `flatpak search <query>` | Search Flathub or other remotes for matching applications. |
| `flatpak info <app_id>` | Show detailed description, size, runtime requirements, and licensing info. |

#### 8.3 System Audits & File Ownership Queries

| Command | Description |
| :--- | :--- |
| `dnf provides <file>` | Find which package provides a specific system file or command (e.g., `dnf provides /usr/bin/git`). |

#### 8.4 Flatpak Permissions & Overrides

| Command | Description |
| :--- | :--- |
| `flatpak info --show-permissions <app_id>` | List permissions requested by the application. |
| `flatpak override --show <app_id>` | Show current overrides for the application. |
| `flatpak override --filesystem=<path> <app_id>` | Override filesystem permissions (e.g., `--filesystem=host` or `--filesystem=/mnt/core`). |
| `flatpak override --reset <app_id>` | Reset all overrides back to default values. |

#### 8.5 DNF Transaction History

| Command | Description |
| :--- | :--- |
| `sudo dnf history list` | List past package transactions with IDs, dates, and action summaries. |
| `sudo dnf history info <id>` | Show detailed package list of a specific transaction. |
| `sudo dnf history undo <id>` | Undo transaction actions (uninstalls installed packages, reinstalls deleted ones). |
| `sudo dnf history redo <id>` | Redo/repeat the transaction. |
| `sudo dnf history rollback <id>` | Revert system state to the point immediately following transaction `<id>`. |
