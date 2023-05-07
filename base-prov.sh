#! /bin/bash

cachelabel='CACHEDISK'
cachedisk="/dev/disk/by-label/$cachelabel"
cachepath='/var/cache/apt-cacher-ng'

# Remove our cron hook... if there is one
if crontab -l > /dev/null 2>&1; then crontab -r; fi

case $1 in
  cron-provans)
    echo '@reboot DEBIAN_FRONTEND=noninteractive /root/base-prov.sh provans > /root/prov.log 2>&1' | crontab
  ;;
  cron-pulldisk)
    echo '@reboot DEBIAN_FRONTEND=noninteractive /root/base-prov.sh pulldisk > /root/prov.log 2>&1' | crontab
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
    if [ -h $cachedisk ]; then
        if [ "$( blkid -o export $cachedisk | grep 'TYPE=' )" = 'TYPE=vfat' ]; then mkfs.xfs -qf -L 'CACHEDISK' $cachedisk; fi
        if [ ! -d '/var/cache/apt-cacher-ng' ]; then mkdir '/var/cache/apt-cacher-ng'; fi
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

if [ "$2" = 'seppuku' ]; then rm -f "$0"; fi
