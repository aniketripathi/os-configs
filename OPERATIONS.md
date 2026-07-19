# os-configs Operations Reference Guide

## About

This document provides a reference of important commands for managing the OS, configurations, backups, and applications.

## Table of Contents

- [1. Apps and Utilities](#1-apps-and-utilities)
- [2. Snapper](#2-snapper)
- [3. Backup Related Commands](#3-backup-related-commands)
- [4. Rclone](#4-rclone)
- [5. System Diagnostics](#5-system-diagnostics)
- [6. Advanced GPU and CPU configuration](#6-advanced-gpu-and-cpu-configuration)
- [7. Firmware](#7-firmware)

## 1. Apps and Utilities

Below is a summary of the key tools and utilities referenced in this guide:

- **snapper** — Btrfs snapshot creation, deletion, and management tool.
- **btrfs** — Administrative utility for Btrfs filesystems to manage space and check disk usage.
- **rclone** — Command-line program to sync files and directories to and from Google Drive cloud storage.
- **pgrep** — Command-line utility to search for active processes by name.
- **systemctl** — Systemd utility to query and control the state of system services and mounts.
- **fwupdmgr** — Command-line client for the fwupd daemon to refresh and update system firmware.
- **switcherooctl** — Utility to list available GPUs and launch applications on specific graphic cards.
- **sensors** — Hardware monitoring tool (lm_sensors) for real-time temperatures, voltages, and fan speeds.
- **watch** — Tool to run commands periodically and view outputs in real-time.
- **cpupower** — Tool to view and configure processor power states and governor settings.
- **powertop** — Power consumption diagnosis and optimization tool.
- **nvtop** — Ncurses-based real-time GPU process monitor for AMD and NVIDIA GPUs.
- **nvidia-smi** — NVIDIA System Management Interface for monitoring and configuring NVIDIA GPUs.
- **radeontop** — Interactive tool to monitor AMD Radeon GPU utilization.
- **powerprofilesctl** — Query and switch active system power profiles.
- **ps** — Utility to report snapshots of current processes.
- **lsof** — Tool to list open files and network connections.
- **du** — Estimate file and directory space usage.
- **ncdu** — Interactive ncurses-based disk usage analyzer.
- **journalctl** — Systemd utility to query and view diagnostic logs.

## 2. Snapper

| Command | Description |
| :--- | :--- |
| `sudo snapper -c root get-config` | Check the configuration settings of the snapper root configuration. |
| `sudo snapper -c root list` | View the list of current snapper snapshots. |
| `sudo snapper -c root create --description "Manual snapshot before doing important work" --cleanup-algorithm number` | Create a manual read-only snapshot before doing important work. |
| `sudo snapper -c root delete <snapshot_number>` | Delete a manual snapshot after verifying the system works fine. |
| `sudo snapper rollback` | Restore snapshots via GRUB: Run rollback from within a booted snapshot to make it permanent. |
| `sudo snapper -c root rollback <snapshot_number>` | Perform a manual rollback to a specific snapshot state directly from the command line. |
| `sudo btrfs filesystem du -s /.snapshots/` | Show the disk space usage of the snapper snapshots. |
| `sudo btrfs filesystem usage /` | View overall filesystem space details. |

## 3. Backup Related Commands

- **Aliases**: Registered automatically in the shell environment via [custom/.profile](file:///mnt/core/os-configs/user-configs/custom/.profile) for systemd service and timer management.
  - `os-configs-status`: List all active timers, their next run schedules, and remaining time.
  - `os-configs-sync-now`: Force-start local files backup and Git push immediately.
  - `os-configs-sync-enable`: Enable and start the weekly Git synchronization timer.
  - `os-configs-sync-disable`: Disable and stop the weekly Git synchronization timer.
  - `os-configs-sync-logs`: View the last 20 log messages for the Git sync service.
  - `os-configs-gdrive-now`: Sync local configurations, compress them, and update Google Drive archive immediately.
  - `os-configs-gdrive-enable`: Enable and start the weekly Google Drive backup timer.
  - `os-configs-gdrive-disable`: Disable and stop the weekly Google Drive backup timer.
  - `os-configs-gdrive-logs`: View the last 20 log messages for the Google Drive backup service.

- **Backup script**: Run [backup-configs.sh](file:///mnt/core/os-configs/user-configs/custom/bin/backup-configs.sh) directly to copy configurations from the live system to the repository directory.
  - **No-Force (Default)**: Compares live files with repository copies. If a file differs (conflict), it is **skipped**; all other non-conflicting files are copied normally.
  - **Force (`-f` or `--force`)**: Copies all files. If a conflict occurs, it backs up the existing repository copy to `backup/repo/` (always overwriting any existing backup file) and overwrites the repository copy with the live version.

  ```shell
  backup-configs.sh [-f | --force]
  ```

- **Restore script**: Run [restore-configs.sh](file:///mnt/core/os-configs/framework/scripts/restore-configs.sh) directly to copy configuration templates from the repository to the live system.
  - **No-Force (Default)**: Compares repository templates with live files. If a file differs (conflict), it is **skipped**; all other non-conflicting files are copied normally.
  - **Force (`-f` or `--force`)**: Restores all files. If a conflict occurs, it backs up the existing live file to `backup/live/` (always overwriting any existing backup file) and overwrites the live version with the repository template.
  
  ```shell
  bash framework/scripts/restore-configs.sh --configs [-f | --force]
  ```

- **Sync & Restore Ordering Rules**:
  - **No-Force Ordering**: Running `backup-configs.sh` and then `restore-configs.sh` (or vice versa) without `--force` results in the second operation being a **no-op**, because non-conflicting files are synced by the first script, and conflicting files are safely skipped by both.
  - **Force Ordering**: Running `backup-configs.sh --force` followed by `restore-configs.sh --force` (or vice versa) makes the second operation a **no-op**, because the first run makes the live and repository states 100% identical.
  - **Manual Conflict Resolution**: You can find conflicting versions saved inside `backup/repo/` and `backup/live/` (preserving their original directory structure) to inspect, compare, and merge manually.

- **Google Drive backup script**: Run [gdrive-backup.sh](file:///mnt/core/os-configs/user-configs/custom/bin/gdrive-backup.sh) directly to compress the repository folder (excluding `.git/`, `keys/`, and the local `backup/` folders) and update the archive on Google Drive.

  ```shell
  gdrive-backup.sh
  ```

- **Git autopush script**: Run [git-autopush.sh](file:///mnt/core/os-configs/user-configs/custom/bin/git-autopush.sh) directly to commit and push changes to the remote Git repository.

  ```shell
  git-autopush.sh
  ```

## 4. Rclone

| Command | Description |
| :--- | :--- |
| `rclone bisync gdrive: /mnt/core/gdrive --resync --resync-mode path1 --dry-run -P` | Perform a dry-run check of manual bi-directional sync between Google Drive and the local directory. |
| `rclone bisync gdrive: /mnt/core/gdrive --resync --resync-mode path1 -P` | Execute a manual bi-directional sync between Google Drive and the local directory. |
| `rclone sync /mnt/core/gdrive gdrive: -P` | Perform manual one-way sync from local `/mnt/core/gdrive` to Google Drive remote. |
| `pgrep -a rclone` | Verify if any active rclone synchronization or mount process is currently running. |
| `systemctl status mnt-core-gdrive.mount` | Inspect systemd status for the dynamically managed Google Drive mount point. |

## 5. System Diagnostics

### Hardware Status (Temps, Fans, Frequency, Power)

| Command | Description |
| :--- | :--- |
| `sensors` | CPU/board temps, fan speeds, voltages. |
| `watch -n1 "grep 'MHz' /proc/cpuinfo"` | Live per-core CPU frequency. |
| `cpupower frequency-info` | Current governor, min/max supported CPU frequency. |
| `sudo powertop` | Live CPU power draw and wakeups. |
| `nvtop` | Live GPU (NVIDIA + AMD) usage, temp, memory, power. |
| `nvidia-smi -q -d TEMPERATURE,CLOCK,POWER,VOLTAGE` | NVIDIA temp/clock/power/voltage detail. |
| `sudo radeontop` | AMD iGPU usage/clock (live). |

### Process & Resource Usage

| Command | Description |
| :--- | :--- |
| `ps -p <pid> -o pid,comm,%cpu,%mem,etime` | Basic process info. |
| `lsof -p <pid>` | Files opened by a process. |
| `sudo lsof -i -a -p <pid>` | Network connections for a process. |
| `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv` | GPU usage per process (NVIDIA). |
| `htop` | Live system-wide CPU/RAM usage. |
| `ps -C <app-name> -o pid,%cpu,%mem,cmd` | CPU/RAM usage of a specific app. |
| `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv \| grep <app-name>` | GPU usage of a specific app. |

### Disk Usage

| Command | Description |
| :--- | :--- |
| `du -sh <path>` | Total size of a file or folder. |
| `du -h --max-depth=1 <path>` | Size broken down one level deep. |
| `ncdu <path>` | Interactive nested disk usage browser. |

### System Logs (Journalctl)

| Command | Description |
| :--- | :--- |
| `journalctl -p err -b` | Errors since last boot. |
| `journalctl -xe` | Recent logs with explanations. |
| `journalctl -f` | Follow logs live. |
| `journalctl --disk-usage` | Total space used by the journal. |

## 6. Advanced GPU and CPU configuration

### GPU Switching & Offloading

| Command | Description |
| :--- | :--- |
| `switcherooctl list` | List available GPUs. |
| `switcherooctl launch <command>` | Launch an app on the discrete (NVIDIA) GPU. |
| `DRI_PRIME=1 <command>` | Force a command onto the discrete GPU (PRIME offload). |
| `DRI_PRIME=0 <command>` | Force a command onto the integrated (AMD) GPU. |

### Power Profiles & CPU Scaling

| Command | Description |
| :--- | :--- |
| `powerprofilesctl list` | List available power profiles. |
| `powerprofilesctl set <power-saver\|balanced\|performance>` | Switch active power profile. |
| `sudo cpupower frequency-set -g <governor>` | Set CPU scaling governor. |
| `sudo cpupower frequency-set -d <min> -u <max>` | Set CPU min/max frequency (e.g. `-d 800MHz -u 4200MHz`). |

### NVIDIA GPU specific configuration

| Command | Description |
| :--- | :--- |
| `sudo nvidia-smi -lgc <min,max>` | Lock NVIDIA GPU clock to a min,max range. |
| `sudo nvidia-smi -rgc` | Reset NVIDIA GPU clock to default. |
| `sudo nvidia-smi -pl <watts>` | Set NVIDIA GPU power limit. |

## 7. Firmware

### Firmware management

| Command | Description |
| :--- | :--- |
| `fwupdmgr refresh` | Refresh firmware metadata. |
| `fwupdmgr get-devices` | List devices with firmware info. |
| `fwupdmgr get-updates` | Check for available firmware updates. |
| `fwupdmgr update` | Apply available firmware updates. |
