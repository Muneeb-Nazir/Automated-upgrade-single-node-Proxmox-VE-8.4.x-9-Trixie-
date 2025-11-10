#!/bin/bash
# ================================================
# 🚀 EvxoTech Proxmox 8.x → 9.x Upgrade Script
# Version: v1.0-17102025
# ================================================

set -e
clear
echo "==============================================="
echo " 🚀 EvxoTech Proxmox 8.x → 9.x Upgrade Script"
echo "==============================================="

# --- Sanity checks
if ! pveversion | grep -q "pve-manager/8"; then
  echo "❌ This system is not running Proxmox VE 8.x."
  echo "Current version: $(pveversion | head -n1)"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script as root!"
  exit 1
fi

echo "🧩 Detected current Proxmox version: $(pveversion | head -n1)"
echo "🧩 Detected Debian codename: $(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)"
sleep 2

# --- Update system and backup important configs
echo "📦 Updating current system and creating backups..."
apt update -y
apt dist-upgrade -y
mkdir -p /root/pve8-backup
cp /etc/apt/sources.list /root/pve8-backup/
cp -r /etc/apt/sources.list.d /root/pve8-backup/
cp /etc/hosts /root/pve8-backup/
cp /etc/network/interfaces /root/pve8-backup/
echo "✅ Backup complete: /root/pve8-backup"

# --- Disable Enterprise Repos
echo "🧹 Disabling enterprise repositories..."
for f in /etc/apt/sources.list.d/*enterprise*; do
  [ -f "$f" ] && mv "$f" "$f.disabled"
done

# --- Replace Debian sources from bookworm → trixie
echo "🛠️  Updating Debian repository sources..."
cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# --- Replace Proxmox sources from bookworm → trixie
echo "🛠️  Updating Proxmox repository sources..."
cat <<EOF >/etc/apt/sources.list.d/pve-no-subscription.list
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
EOF

# --- Optional: disable Ceph enterprise repos
echo "🧹 Disabling Ceph enterprise repos if present..."
if ls /etc/apt/sources.list.d/*ceph*enterprise* >/dev/null 2>&1; then
  for f in /etc/apt/sources.list.d/*ceph*enterprise*; do
    mv "$f" "${f}.disabled"
  done
fi

# --- Clean up
apt clean
apt update -y

echo "🔍 Checking available upgrades..."
apt list --upgradable | grep -E "proxmox|kernel|systemd" || true
sleep 3

echo "⚙️  Starting full upgrade to Proxmox VE 9 (Debian 13 Trixie)..."
apt full-upgrade -y

echo "🧹 Removing obsolete packages..."
apt autoremove -y --purge

# --- Optional: ensure pve9 repo is active
echo "✅ Ensuring Proxmox 9 repo is set correctly..."
grep -q "pve trixie" /etc/apt/sources.list.d/pve-no-subscription.list || \
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# --- Final update
apt update -y
apt dist-upgrade -y

echo "==============================================="
echo " ✅ Upgrade process complete!"
echo " 💡 Recommended next steps:"
echo "    1. Reboot your node: reboot"
echo "    2. After reboot, verify:"
echo "         pveversion"
echo "         cat /etc/os-release | grep VERSION_CODENAME"
echo "    3. Run post-install script:"
echo "         ./post-pve9-install-v1.2-18102025.sh"
echo "==============================================="
