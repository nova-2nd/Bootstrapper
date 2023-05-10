#! /bin/bash

cachelabel='CACHEDISK'
cachedisk="/dev/disk/by-label/$cachelabel"
cachepath='/var/cache/apt-cacher-ng'

# Remove our cron hook... if there is one
crontab -l > /dev/null 2>&1 && crontab -r; echo 'Cron hook removed' >> /root/prov.log 2>&1

# Check if we are in a chroot jail
[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ] && jailed=1 || jailed=0

case $1 in
  cron-provans)
    echo '@reboot DEBIAN_FRONTEND=noninteractive /root/base-prov.sh provans >> /root/prov.log 2>&1' | crontab
  ;;
  cron-pulldisk)
    echo '@reboot DEBIAN_FRONTEND=noninteractive /root/base-prov.sh pulldisk >> /root/prov.log 2>&1' | crontab
  ;;
  decron)
    crontab -r
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
  provans)
    ### Provision ansible
    ###
    rm -rf /var/lib/ansible
    apt-get install python3-venv -y
    python3 -m venv /var/lib/ansible
    # shellcheck source=/dev/null
    source /var/lib/ansible/bin/activate
    pip install -U pip setuptools wheel
    pip install ansible
    deactivate
    for file in /var/lib/ansible/bin/ansible*; do ln -sf "$file" "/usr/local/sbin/${file##*/}"; done
    ###
    ### Provision ansible
  ;;
  provcache)
    if [ -h $cachedisk ] && [ $jailed = 0 ]; then
        [ "$( blkid -o export $cachedisk | grep 'TYPE=' )" = 'TYPE=vfat' ] && mkfs.xfs -qf -L $cachelabel $cachedisk
        [ ! -d '/var/cache/apt-cacher-ng' ] && mkdir '/var/cache/apt-cacher-ng'
        echo "$cachedisk $cachepath xfs defaults 0 0" >> /etc/fstab
        mount "$cachedisk"
        chown -R '19484:109' "$cachepath"
        chmod -R 2775 "$cachepath"
        echo 'apt-cacher-ng apt-cacher-ng/tunnelenable boolean false' | debconf-set-selections
        apt-get -y install apt-cacher-ng
        echo 'Acquire::http { Proxy "http://127.0.0.1:3142"; }' > /etc/apt/apt.conf.d/proxy
    fi
  ;;
esac

# Remove ourself
# [ "$2" = 'seppuku' ] && rm -f "$0"
