#!/bin/bash
# ======================================================
# 🧯 EvxoTech Proxmox 9 → 8 Rollback & Recovery Helper
# Version: v1.0-17102025
# ======================================================

set -e
clear
echo "======================================================"
echo " 🧯 EvxoTech Rollback to Proxmox VE 8 (Debian 12)"
echo "======================================================"

# --- Verify backup directory exists
if [ ! -d "/root/pve8-backup" ]; then
  echo "❌ Backup directory not found: /root/pve8-backup"
  echo "You can only use this rollback if the upgrade script created the backup."
  exit 1
fi

# --- Ask for confirmation
read -p "⚠️  This will restore your /etc/apt and network configs from backup. Continue? (y/N): " ans
case "$ans" in
  y|Y) echo "Proceeding..." ;;
  *) echo "Cancelled."; exit 0 ;;
esac

# --- Stop apt/dpkg processes
echo "🧩 Stopping any APT or dpkg locks..."
systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*

# --- Restore sources and configs
echo "🗂️  Restoring repository and configuration backups..."
cp /root/pve8-backup/sources.list /etc/apt/sources.list -f
cp -r /root/pve8-backup/sources.list.d /etc/apt/sources.list.d -rf
cp /root/pve8-backup/hosts /etc/hosts -f
cp /root/pve8-backup/interfaces /etc/network/interfaces -f
echo "✅ Repositories and network files restored."

# --- Revert to Proxmox 8 (Bookworm) repositories
echo "🛠️  Setting official Proxmox 8 and Debian 12 (Bookworm) sources..."
cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

cat <<EOF >/etc/apt/sources.list.d/pve-no-subscription.list
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

# --- Clean up and refresh
apt clean
apt update -y || true

echo "🔍 Reverting system packages to Proxmox 8 versions..."
apt install -f -y
apt dist-upgrade -y || true
apt autoremove -y --purge || true

echo "======================================================"
echo " ✅ Rollback preparation complete!"
echo " 💡 Recommended next steps:"
echo "   1. Verify your repo list: cat /etc/apt/sources.list"
echo "   2. Run: apt update && apt dist-upgrade -y"
echo "   3. Reboot the node: reboot"
echo "======================================================"
