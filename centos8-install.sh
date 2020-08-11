# Set up kickstart of CentOS 8 suitable for AMI

version=8
# You should choose mirrors here that are close to the AWS location you are building in
# or use your own mirror
mirror=http://mirror.vcu.edu/pub/gnu_linux/centos/
epelmirror=http://mirror.umd.edu/fedora/epel

# Detect primary root drive - also determines ethernet name
if [ -e /dev/nvme0n1 ]; then
  drive=nvme0n1
  bootpart=nvme0n1p1
  nic=ens5
elif [ -e /dev/xvda ]; then
  drive=xvda
  bootpart=xvda1
  nic=eth0
fi

echo Drive is $drive

# Download boot kernal and ramdisk to local drive
yum -y install wget
mkdir /boot/bootstrap
cd /boot/bootstrap
wget ${mirror}/${version}/BaseOS/x86_64/os/isolinux/vmlinuz
wget ${mirror}/${version}/BaseOS/x86_64/os/isolinux/initrd.img

# Create the kickstart file that will be booted
echo "Creating kickstart"

# Note that within the kickstart, we also create the cloud-init config file
cat > /boot/bootstrap/kickstart.ks << EOKSCONFIG
# Text install (Graphics are useless here, it's all automated)
text

# Install from scratch
install

# Don't run the Setup Agent on first boot
firstboot --disable

# Accept the  agreement (otherwise it will stop and ask)
eula --agreed

# We don't need X configured on an AMI
skipx

# Specify the repository locations we are downloading from
url --url="${mirror}/${version}/BaseOS/x86_64/os/"
repo --name="base" --baseurl=${mirror}/${version}/BaseOS/x86_64/os/
repo --name="AppStream" --baseurl=${mirror}/${version}/AppStream/x86_64/os/
repo --name="extras" --baseurl=${mirror}/${version}/extras/x86_64/os/
repo --name="epel" --baseurl=${epelmirror}/${version}/Everything/x86_64/

# Set up localization
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/New_York --isUtc --ntpservers=0.centos.pool.ntp.org,1.centos.pool.ntp.org,2.centos.pool.ntp.org,3.centos.pool.ntp.org

# We must always use DHCP
network --onboot yes --bootproto dhcp --ipv6=auto --activate

# Lock the root password - access by key only
rootpw --lock --iscrypted "*"

# firewalld is normally off in AWS - use Security Groups instead
# If you want it on, you can use this at a minimum for the rest to work:
# firewall --enabled --ssh
firewall --disabled

# You can leave this on if desired
selinux --disabled

# Specify how the bootloader should be installed (required)
bootloader --location=mbr --append="crashkernel=auto rhgb quiet" --timeout=0

# Initialize the disk we detected
ignoredisk --only-use=$drive
zerombr
clearpart --all --initlabel --drives=$drive

# Create primary system partitions (required for installs)
part /boot --fstype=xfs --size=512 --asprimary --ondrive=$drive
part pv.00 --grow --size=1 --ondrive=$drive

# Create a Logical Volume Management (LVM) group (optional)
volgroup vg_root pv.00

# Create particular logical volumes (optional)
logvol / --fstype=xfs --name=root --vgname=vg_root --size=1 --grow

# Service configuration
services --enabled=NetworkManager,sshd,chronyd,tuned

# Packages selection (%packages section is required)
%packages

@^server-product-environment
@guest-agents
kexec-tools

# Cloud init bootstraps instances based on this AMI
cloud-init
cloud-utils-growpart
tuned

# We're viritual - we don't need these firmware packages
-aic94xx-firmware
-atmel-firmware
-b43-openfwwf
-bfa-firmware
-ipw2100-firmware
-ipw2200-firmware
-ivtv-firmware
-iwl100-firmware
-iwl105-firmware
-iwl135-firmware
-iwl1000-firmware
-iwl2000-firmware
-iwl2030-firmware
-iwl3160-firmware
-iwl3945-firmware
-iwl4965-firmware
-iwl5000-firmware
-iwl5150-firmware
-iwl6000-firmware
-iwl6000g2a-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-iwl7260-firmware
-libertas-usb8388-firmware
-ql2100-firmware
-ql2200-firmware
-ql23xx-firmware
-ql2400-firmware
-ql2500-firmware
-rt61pci-firmware
-rt73usb-firmware
-xorg-x11-drv-ati-firmware
-zd1211-firmware

%end

# Create the cloud config file
%post --log=/var/log/anaconda/post.log
# cloud-init config
echo "Creatling cloud config"
mkdir -p /etc/cloud/
echo "---
users:
 - default

preserve_hostname: false

# This is our pre-base image. Update packages.
package_update: true
package_reboot_if_required: true

# SSH Configuration
disable_root: true
ssh_pwauth: no
ssh_deletekeys: true
ssh_genkeytypes: ~

syslog_fix_perms: ~

system_info:
  default_user:
    name: centos
    lock_passwd: false
    # password hash below corresponds to a default password of: centos
    # We don't want this - cloud init will be used to set up ssh key.
    # passwd: ** SOMECRYPT **
    gecos: Administrator
    groups: [wheel, adm, systemd-journal]
    sudo: [\"ALL=(ALL) NOPASSWD:ALL\"]
    shell: /bin/bash
  distro: rhel
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
  ssh_svcname: sshd

# Edit these to our taste
cloud_init_modules:
 - migrator
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - rsyslog
 - users-groups
 - ssh

cloud_config_modules:
 - mounts
 - locale
 - set-passwords
 - yum-add-repo
 - package-update-upgrade-install
 - timezone
 - puppet
 - chef
 - salt-minion
 - mcollective
 - disable-ec2-metadata
 - runcmd

cloud_final_modules:
 - rightscale_userdata
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message
" > /etc/cloud/cloud.cfg

%end
reboot --eject
EOKSCONFIG

# Set up the boot configuration to initiate the kickstart
echo "Creating GRUB config"

echo "menuentry 'centosinstall' {
        set root='hd0,msdos1'
    linux /boot/bootstrap/vmlinuz ip=dhcp ksdevice=${nic} ks=hd:${bootpart}:/boot/bootstrap/kickstart.ks method=${mirror}/${version}/BaseOS/x86_64/os/ lang=en_US keymap=us
        initrd /boot/bootstrap/initrd.img
}" >> /etc/grub.d/40_custom

cat > /etc/default/grub <<DEFGRUBFILE
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto rd.lvm.lv=vg_root/root"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
DEFGRUBFILE

echo "Running Grub config"
grub2-set-default 'centosinstall'
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Rebooting - this will take a while - kickstart will take place"
reboot
