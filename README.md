# Automated-upgrade-single-node-Proxmox-VE-8.4.x-9-Trixie-
Carefully crafted, fully automated but safe upgrade script to move a single-node Proxmox VE 8.4.x → 9 (Trixie).
carefully crafted, fully automated but safe upgrade script to move a single-node Proxmox VE 8.4.x → 9 (Trixie).
It follows the step-by-step plan we discussed: backups → repo changes → key fixes → safe upgrade → cleanup → reboot prompt. It tries to be conservative (backs up VMs and configs, preserves important files like lvm.conf, warns you about Ceph & enterprise repos, logs everything).

Read the whole message first. Then copy the script into /root/upgrade-pve8-to-pve9.sh, chmod +x, and run it as root. The script prompts for confirmation at major steps.

What this script does (high level)

Checks current Proxmox version and alerts if not 8.4.x (warns but continues).

Creates an archive backup directory and runs vzdump --all to backup all VMs/LXCs (snapshot mode if possible).

Archives /etc/pve, /root important files and existing apt sources.

Replaces apt sources with Debian Trixie + Proxmox pve trixie (no-subscription) and disables enterprise repo & Ceph Bookworm/Trixie entries.

Installs/updates required packages (curl, gnupg), imports Debian + Proxmox GPG keys into /usr/share/keyrings.

Runs apt update and apt full-upgrade -y (shows output and logs to /root/pve9-upgrade.log).

Preserves your lvm.conf (asks if user wants to keep or install the package maintainer version when prompted).

Runs update-initramfs and updates grub (done automatically by package hooks).

Optionally removes old kernels (keeps latest 2) — commented out by default.

Reboots only after your explicit confirmation.

Important warnings (read!)

If you run a Ceph cluster or use Proxmox Backup Server or have a multi-node cluster, do not run this script blindly. Stop and tell me — I will give cluster-specific steps. This script is for single-node (non-Ceph) or nodes where you are prepared for manual Ceph handling.

If you have a paid Proxmox subscription and rely on enterprise repo, the enterprise repo will be disabled (script comments it out). You can re-enable it after upgrading if you have credentials.

This script will backup VMs but you should still ensure external backups exist before proceeding.

How to run (one-liner)
curl -fsSL -o /root/upgrade-pve8-to-pve9.sh 'data:text/plain;base64,{{BASE64}}' && chmod +x /root/upgrade-pve8-to-pve9.sh && /root/upgrade-pve8-to-pve9.sh


(Replace {{BASE64}} with the base64 of the script if you want to download via data URL; simplest is to paste the script into /root/upgrade-pve8-to-pve9.sh and run it.)

Better:

nano /root/upgrade-pve8-to-pve9.sh
# paste script, save
chmod +x /root/upgrade-pve8-to-pve9.sh
/root/upgrade-pve8-to-pve9.sh

After the upgrade

Reboot (if you didn’t earlier).

Verify:

pveversion
uname -r
apt update


Check VMs, storage, network bridges, firewall VM (OPNsense) and confirm everything boots.

If you see any APT repo or GPG key warnings, copy the relevant apt update output and paste here — I will help fix quickly.

Keep an eye on the log /root/pve9-upgrade.log.
