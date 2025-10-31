#!/bin/bash
# upgrade-pve8-to-pve9.sh
# Safely upgrade Proxmox VE 8.4.x -> 9 (Trixie)
# Usage: save and run as root: chmod +x upgrade-pve8-to-pve9.sh && ./upgrade-pve8-to-pve9.sh
set -euo pipefail
LOG=/root/pve9-upgrade.log
exec > >(tee -a "${LOG}") 2>&1

echo
echo "=================================================================="
echo " Proxmox VE 8.x -> 9 (Trixie) upgrade script"
echo " - Backup VMs, replace apt repos, import keys, perform full-upgrade"
echo " - Log file: ${LOG}"
echo "=================================================================="
date

# Basic checks
CURRENT_PVE_VERSION="$(pveversion 2>/dev/null || true)"
KERNEL="$(uname -r || true)"
echo "Detected pveversion: ${CURRENT_PVE_VERSION}"
echo "Running kernel: ${KERNEL}"
echo
echo "*** IMPORTANT: If you use Ceph or run a multi-node cluster, STOP now and run a cluster-aware upgrade procedure. ***"
echo

read -p "Are you upgrading a single-node (non-Ceph) Proxmox server and have external backups? (type YES to continue) " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "Aborting per user request."
  exit 1
fi

# Create backup directories
BACKUP_DIR="/root/pve9-backups-$(date +%F-%H%M%S)"
mkdir -p "${BACKUP_DIR}"
echo "Created backup dir: ${BACKUP_DIR}"

# 1) Export OPNsense / important configs if present
echo
echo "Backing up /etc/pve and apt sources..."
tar -czpf "${BACKUP_DIR}/etc-pve-$(date +%F).tgz" /etc/pve || echo "Warning: /etc/pve tar failed"
cp -a /etc/apt/sources.list* "${BACKUP_DIR}/" || true
cp -a /etc/apt/sources.list.d "${BACKUP_DIR}/" || true

# 2) Backup all VMs & LXCs using vzdump
echo
echo "Starting vzdump backup of all VMs/LXCs (snapshot mode where supported) to ${BACKUP_DIR}..."
if command -v vzdump >/dev/null 2>&1; then
  # Try snapshot mode; if not supported for a container, vzdump will manage.
  vzdump --all --mode snapshot --compress zstd --dumpdir "${BACKUP_DIR}" --quiet 0 || {
    echo "vzdump reported non-zero exit; please inspect ${BACKUP_DIR} for partial backups. Continuing."
  }
else
  echo "vzdump not found; skipping VM backups. This is unexpected on Proxmox. Aborting."
  exit 1
fi

# 3) Save list of VMs and storage status
qm list > "${BACKUP_DIR}/qm-list-$(date +%F).txt" || true
pct list > "${BACKUP_DIR}/pct-list-$(date +%F).txt" || true
pvesm status > "${BACKUP_DIR}/pvesm-status-$(date +%F).txt" || true

# 4) Prepare apt repos: backup and replace
echo
echo "Backing up apt sources to ${BACKUP_DIR} and replacing with Trixie (Proxmox 9) community repos..."
cp -a /etc/apt/sources.list /etc/apt/sources.list.bak || true
cp -a /etc/apt/sources.list.d "${BACKUP_DIR}/sources.list.d.bak" || true

# Write clean sources.list for Debian Trixie
cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
EOF

# Remove subscription/enterprise and old ceph files from sources.list.d (we'll add no-subscription pve entry)
rm -f /etc/apt/sources.list.d/pve-enterprise.list || true
rm -f /etc/apt/sources.list.d/ceph*.list || true
rm -f /etc/apt/sources.list.d/*proxmox*.list || true

# Add Proxmox community repo file (no subscription)
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<'EOF'
deb http://download.proxmox.com/debian/pve trixie
EOF

echo "APT sources prepared."

# 5) Install helper packages and import keys
echo
echo "Installing prerequisites (curl, gnupg) and importing official keys..."
apt update -y
apt install -y --no-install-recommends curl gnupg ca-certificates apt-transport-https

# Import Debian archive keys (Debian 13)
curl -fsSL https://ftp-master.debian.org/keys/archive-key-13.asc | gpg --dearmor -o /usr/share/keyrings/debian-archive-keyring.gpg || true
curl -fsSL https://ftp-master.debian.org/keys/archive-key-13-security.asc | gpg --dearmor -o /usr/share/keyrings/debian-security-archive-keyring.gpg || true

# Import Proxmox release key (trixie). Try a few known locations; fall back to the download site.
set +e
curl -fsSL https://download.proxmox.com/debian/proxmox-release-trixie.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg
if [ $? -ne 0 ]; then
  echo "Primary Proxmox key URL failed, trying enterprise mirror..."
  curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg || {
    echo "Warning: could not fetch official Proxmox trixie key via standard URLs. Proceeding — apt may warn. Please check /usr/share/keyrings/proxmox-archive-keyring.gpg"
  }
fi
set -e

# 6) apt update to refresh lists with new keys (if present)
apt clean
apt update -y || {
  echo "apt update returned non-zero. Continuing but please review output in ${LOG}."
}

# 7) Run full-upgrade (this is the main step)
echo
echo "==> Starting apt full-upgrade. This may take a while. Logs: ${LOG}"
echo "When prompted about config files (e.g., /etc/lvm/lvm.conf), choose 'N' to keep your existing file (recommended) unless you know you need the vendor version."
read -p "Type YES to start full-upgrade now: " GOUP
if [[ "${GOUP}" != "YES" ]]; then
  echo "Upgrade canceled by user. Exiting."
  exit 1
fi

# Perform the full upgrade
# Use DEBIAN_FRONTEND=readline so prompts appear for config files (so you'll be interactive)
DEBIAN_FRONTEND=readline apt full-upgrade -y || {
  echo "apt full-upgrade failed. Check ${LOG} for details. Exiting."
  exit 1
}

# 8) Run package config and housekeeping
echo
echo "Running apt --fix-broken and autoremove..."
apt --fix-broken install -y || true
apt autoremove -y || true
apt clean

# 9) Update initramfs and grub (package hooks normally do this)
echo "Updating initramfs and regenerating grub/menu..."
update-initramfs -u -k all || true
update-grub || true

# 10) Show current pveversion and kernel
echo
echo "Upgrade finished. Current versions:"
pveversion || true
uname -a || true

# 11) Optional: remove old kernels (commented out by default)
echo
echo "Old kernel cleanup is available but disabled by default. You can remove old proxmox-kernel packages manually if desired."

# 12) Final instructions and reboot prompt
echo
echo "Upgrade log is at ${LOG}."
echo "Please check the log carefully before rebooting. Recommended next step: reboot to boot into new kernel."
read -p "Reboot now? Type REBOOT to reboot, anything else to skip: " RB
if [[ "${RB}" == "REBOOT" ]]; then
  echo "Rebooting now..."
  sleep 3
  reboot
else
  echo "Skipping reboot. Reboot when ready with: reboot"
fi

exit 0
