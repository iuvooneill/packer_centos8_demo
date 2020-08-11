echo "Running Preparation and Finalization"

# Can we detect that we were successful and CentOS 8 is installed?
major=$(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1)

echo "Running version $major"
if [ $major != 8 ]; then
    echo "ERROR: We aren't running CentOS 8?"
    exit -1
fi

# Save date of build so we can verify
date > /etc/date-of-build

# Make post-setup adjustments - eliminate menu timeout, set root device
cat > /etc/default/grub <<'DEFGRUBFILE'
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto rd.lvm.lv=vg_root/root"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
DEFGRUBFILE

echo "Running grub"
grub2-mkconfig -o /boot/grub2/grub.cfg
# This forces all drivers to be included, so we can run on any instance type
echo "Running dracut"
dracut --regenerate-all --force --no-hostonly

# Create a service to run this the first time we boot
echo "Creating growroot service file"
cat > /etc/systemd/system/growroot.service <<'ENDGROWSERVICE'
[Unit]

[Service]
ExecStart=/bin/bash /var/tmp/growroot.sh

[Install]
WantedBy=default.target
ENDGROWSERVICE

# cloud-init will not resize a root volume that is LVM :( So we need to create a script
# to run on first boot that does it for us. We only need it to run the very first boot,
# so the script disables and removes itself at the end.
echo "Creating growroot.sh"
cat > /var/tmp/growroot.sh <<'ENDGROWROOT'
# Determine root LVM partition - could be sda, xvda, nvmeX...
ROOTPART="$(pvs | grep vg_root | awk '{print $1}')"
PARTNAME=${ROOTPART#/dev/}
DEVLINK=`readlink /sys/class/block/$PARTNAME`
DISKNAME=`echo $DEVLINK | sed 's/.*\/\(.*\)\/.*$/\1/'`
PARTNUM="$(cat /sys/class/block/$PARTNAME/partition)"
# Resize partition
growpart /dev/$DISKNAME $PARTNUM
pvresize $ROOTPART
# VG automatically resizes
lvextend -l+100%FREE /dev/mapper/vg_root-root
xfs_growfs /
# Disable service that ran this script
systemctl disable growroot
# Remove the service file
rm -f /etc/systemd/system/growroot.service
systemctl daemon-reload
# Remove this script
rm -f /var/tmp/growroot.sh
ENDGROWROOT

# Enable the growroot service at boot time
chmod 755 /etc/systemd/system/growroot.service
systemctl daemon-reload
systemctl enable growroot

# Cleanup yum/dnf cache
dnf -y clean all

# Stop logging for cleanup
service rsyslog stop
service auditd stop

# Clean up logs - rotate all rsyslog logs first
logrotate -f /etc/logrotate.conf
rm -f /var/log/*-???????? /var/log/*.gz /var/log/anaconda /var/log/dmesg.old

# These need to be truncated
cat /dev/null > /var/log/lastlog
cat /dev/null > /var/log/audit/audit.log
cat /dev/null > /var/log/wtmp
cat /dev/null > /var/log/grubby

# cleanup udev peristent naming rules, and make the ifcfg-* files generic
rm -f /etc/udev/rules.d/70*
sed -i '/UUID/d' /etc/sysconfig/network-scripts/ifcfg-e*
sed -i '/HWADDR/d' /etc/sysconfig/network-scripts/ifcfg-e*

# Cleanup host and user SSH keys
rm -f /etc/ssh/*key*
rm -rf ~/.ssh/

# Clean up user history
rm -f ~/.bash_history
unset HISTFILE

echo "Finalize completed. AMI will now be generated."
