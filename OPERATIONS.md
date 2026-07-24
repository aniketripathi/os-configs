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
| `switcherooctl` | Utility to list available GPUs and launch applications using specific graphics cards. |
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

- **Default:** Compares live files with repository files, copying only non-conflicting files.
- **Force (`-f` or `--force`):** Overwrites repository files with live versions.
- **Repository Pruning:** Removes untracked files in the repository no longer listed in `restore.conf`.

#### 3.4 Restore Script

Run the restore script directly to copy configuration templates from the repository to the live system:

```shell
bash framework/scripts/restore-configs.sh --configs [-f | --force]
```

- **Default:** Compares repository templates with live files, restoring only non-conflicting files.
- **Force (`-f` or `--force`):** Overwrites live files with repository templates.

#### 3.5 Execution Ordering Rules

Running the backup and restore operations in sequence has specific outcomes depending on which script is executed first:

- **No-Force Ordering:** Running `backup-configs.sh` and then `restore-configs.sh` (or vice versa) without `--force` results in the second operation being a no-op. Non-conflicting files are synced by the first script, and conflicting files are safely skipped by both.
- **Force Ordering:** Running `backup-configs.sh --force` followed by `restore-configs.sh --force` (or vice versa) makes the second operation a no-op because the first run ensures that the live and repository states are identical.
- **Conflict Archives:** The backup directories (`backup/live/` or `backup/repo/`) will contain the overridden versions of the conflicting files based on which script was run first (e.g., if you run the backup script first, the old repository copy is saved in `backup/repo/`).
- **Overwritten Warnings:** Any backup files saved in `backup/live/` or `backup/repo/` are temporary and will be overwritten on the next run if the same conflict occurs again. Compare and manually merge the changes between your live system files and repository files before running the scripts again to avoid losing the older state.

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

**Restore List (`framework/configs/restore.conf`)** — This is the master list of tracked files. If you want to add new configurations to be backed up or remove old ones from tracking, edit this file at the repository level.

**All Other Configurations (Home & System)** — Any other files (such as `.bashrc`, `.config/powerdevilrc`, or system files under `/etc/`) must be updated at their real live paths (e.g., in your home directory or `/etc/`) and **not** inside the repository directory. Once updated on the live system, run the backup script to sync them into the repository.

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
| `switcherooctl list` | List available GPUs. |
| `switcherooctl launch <command>` | Launch an app on the discrete (NVIDIA) GPU. |
| `DRI_PRIME=1 <command>` | Force a command onto the discrete GPU (PRIME offload). |
| `DRI_PRIME=0 <command>` | Force a command onto the integrated (AMD) GPU. |

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
