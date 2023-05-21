#! /bin/sh

echo '################################################################################'
echo "# shellglue task $1 executing..."

systemdisk=/dev/sda
logfile=/var/log/installer/shellglue.log

case "$1" in
  playprov)
    "$0" enable-deb-proxy
    "$0" provans
  ;;
  enable-deb-proxy)
    echo 'Acquire::http::Proxy "http://localhost:8000/";' > /etc/apt/apt.conf.d/99squidcache
    echo 'APT::Keep-Downloaded-Packages "0";' > /etc/apt/apt.conf.d/99nolocalcache
    systemctl disable squid
    echo 'shutdown_lifetime 0' >> /etc/squid-deb-proxy/squid-deb-proxy.conf
    while ! systemctl -q is-active squid-deb-proxy.service; do echo 'Waiting...'; sleep 1; done
    apt-get update
  ;;
  provans)
    ### Provision ansible
    ###
    rm -rf /var/lib/ansible
    apt-get -qy install python3-venv
    python3 -m venv /var/lib/ansible
    # shellcheck source=/dev/null
    . /var/lib/ansible/bin/activate
    pip install -U pip setuptools wheel
    pip install ansible
    deactivate
    for file in /var/lib/ansible/bin/ansible*; do ln -sf "$file" "/usr/local/bin/${file##*/}"; done
    ###
    ### Provision ansible
  ;;
  di-early-hook)
    echo 'This is the early hook on stdout'
    echo 'This is the early hook on stderr' >&2
    "$0" di-patch
  ;;
  di-partman-hook)
    echo 'This is the partman hook on stdout'
    echo 'This is the partman hook on stderr' >&2
    "$0" di-partition-disk
    cp -r /hd-media/files/prov/final-partman/* /var/lib/partman/
  ;;
  di-late-hook)
    echo 'This is the late hook on stdout'
    echo 'This is the late hook on stderr' >&2
    cp "$0" /target/root/
    in-target --pass-stdout /root/shellglue.sh cron playprov
  ;;
  di-patch)
    cp /hd-media/files/prov/kernel-mod/*.ko /lib/modules/5.10.0-22-amd64/
    depmod -a
    cp /hd-media/files/prov/thin_check/libexpat.so.1 /usr/lib/x86_64-linux-gnu/
    cp /hd-media/files/prov/thin_check/libstdc\+\+.so.6 /lib/x86_64-linux-gnu/
    cp /hd-media/files/prov/thin_check/pdata_tools /usr/sbin/thin_check
    chmod +x /usr/sbin/thin_check
  ;;
  di-partition-disk)
    "$0" sfdisk-recipe-1
    "$0" lvm-recipe-1
  ;;
  sfdisk-recipe-1)
    sfdisk -X gpt $systemdisk << EOF
size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
size=512M, type=BC13C2FF-59E6-4262-A352-B275FD6F7172
type=E6D6D379-F507-44C2-A23C-238F2A3DF928
EOF
  ;;
  lvm-recipe-1)
    pvcreate /dev/sda3
    vgcreate vgdisk /dev/sda3
    lvcreate --thin-pool tpool0 --extents +100%FREE --poolmetadatasize 256M vgdisk
    lvcreate --thin --name swap --virtualsize 3GiB vgdisk/tpool0
    lvcreate --thin --name root --virtualsize 10GiB vgdisk/tpool0
    lvcreate --thin --name var_log --virtualsize 4GiB vgdisk/tpool0
    lvcreate --thin --name home --virtualsize 4GiB vgdisk/tpool0
    vgchange -ay
    # mkfs.xfs -f /dev/disk/by-label/CACHEDISK -L CACHEDISK
  ;;
  parted-recipe-1)
    parted -s $systemdisk mklabel gpt \
      mkpart ESP 0% 1% set 1 esp on \
      mkpart BOOT 1% 3% set 2 bls_boot on \
      mkpart LVM 3% 100% set 3 lvm on
  ;;
  fdisk-recipe-1)
    printf 'g\nw\n' | fdisk $systemdisk
    printf 'n\n1\n\n+256M\nw\n' | fdisk $systemdisk
    printf 'n\n2\n\n+512M\nw\n' | fdisk $systemdisk
    printf 'n\n3\n\n\nw\n' | fdisk $systemdisk
    printf 't\n1\n1\nw\n' | fdisk $systemdisk
    printf 't\n2\n48\nw\n' | fdisk $systemdisk
    printf 't\n3\n30\nw\n' | fdisk $systemdisk
  ;;
  format-recipe-1)
    mkfs.fat /dev/sda1
    mkfs.xfs /dev/sda2
    mkfs.xfs /dev/mapper/vgdisk-root
    mkfs.xfs /dev/mapper/vgdisk-home
    mkfs.xfs /dev/mapper/vgdisk-var_log
    # mkfs.xfs /dev/disk/by-label/CACHEDISK -L CACHEDISK
    mkswap /dev/mapper/vgdisk-swap
  ;;
  di-mount-chroot)
    mkdir /target
    mount -t xfs /dev/mapper/vgdisk-root /target
    mkdir /target/boot
    mount -t xfs /dev/sda2 /target/boot
    mkdir /target/boot/efi
    mount -t vfat /dev/sda1 /target/boot/efi
    mkdir /target/home
    mount -t xfs /dev/mapper/vgdisk-home /target/home
    mkdir -p /target/var/log
    mount -t xfs /dev/mapper/vgdisk-var_log /target/var/log
    mkdir /target/var/cache
    mount -t xfs /dev/disk/by-label/CACHEDISK /target/var/cache
    mkdir /target/dev
    mount --bind /dev /target/dev
    mount --bind /dev/pts /target/dev/pts
    mkdir /target/proc
    mount --bind /proc /target/proc
    mkdir /target/sys
    mount --bind /sys /target/sys
  ;;
  pulldisk)
    ### Pull files
    ### Pull provisiongin files from installdisk
    mount /dev/disk/by-label/INSTALLDISK /mnt/
    cp -r /mnt/files/prov /root/
    umount /mnt/
    ###
    ### Pull files
  ;;
  breakpoint)
    # break free with echo -e '\n' > /var/breakfifo
    mknod /var/breakfifo p
    read -r < /var/breakfifo > /dev/null
    rm -f /var/breakfifo
  ;;
  cron)
    echo "@reboot root \
      DEBIAN_FRONTEND=noninteractive /root/shellglue.sh $2 >> $logfile 2>&1; \
      rm -f /etc/cron.d/shellglue-$2 >> $logfile 2>&1" > "/etc/cron.d/shellglue-$2"
  ;;
  echo) echo "$2";;
  envdump) set;;
  seppuku) rm -f "$0";;
esac

echo "# shellglue task $1 done"
echo '################################################################################'
