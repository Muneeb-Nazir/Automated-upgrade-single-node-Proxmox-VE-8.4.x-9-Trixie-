🧩 Usage

Save it as:

nano rollback-to-proxmox8-v1.0-17102025.sh


Paste the content above, then:

chmod +x rollback-to-proxmox8-v1.0-17102025.sh
./rollback-to-proxmox8-v1.0-17102025.sh

💡 Notes

Works only if /root/pve8-backup/ exists (created by the upgrade script).

Does not downgrade Proxmox packages automatically — it simply restores repos/configs so you can safely reinstall or realign package versions.

After rollback, you can run:

apt update && apt dist-upgrade -y


to realign to Proxmox 8.
