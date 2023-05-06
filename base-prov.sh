#! /bin/bash

# Remove our cron hook, if there is one
if crontab -l > /dev/null && [ "$1" != "decron" ]; then $0 decron; fi

case $1 in
  cron-provans)
    echo "@reboot /root/base-prov.sh provans" | crontab
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
    source /var/lib/ansible/bin/activate
    pip install -U pip setuptools wheel
    pip install ansible
    deactivate
    for file in /var/lib/ansible/bin/ansible*; do ln -sf "$file" "/usr/local/sbin/${file##*/}"; done
    ###
    ### Provision ansible
    ;;
esac

if [ "$2" = 'seppuku' ]; then rm -f "$0"; fi
