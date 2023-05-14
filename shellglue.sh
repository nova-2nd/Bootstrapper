#! /bin/sh

echo '################################################################################'
echo "# shellglue task $1 executing..."

cachefs=xfs
cachelabel=CACHEDISK
cachedisk=/dev/disk/by-label/$cachelabel
cachemount=/var/cache
logfile=/var/log/installer/shellglue.log
gotojail=0

# getopts
# shift $cachelabel

# Check if we are in a chroot jail
# [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ] && jailed=1 || jailed=0 #  && [ $jailed = 0 ]

case "$1" in
  prov-cache-disk)
    [ "$( blkid -o export $cachedisk | grep 'TYPE=' )" != "TYPE=$cachefs" ] && mkfs.$cachefs -qf -L $cachelabel $cachedisk; echo "Formatted $cachedisk as $cachefs"
    [ ! -d $cachepath ] && mkdir $cachepath; echo "Added cachefolder $cachepath"
    [ "$( cat /target/etc/fstab | grep -w $cachedisk )" = '' ] && echo "$cachedisk /var/cache/apt-cacher-ng $cachefs defaults 0 0" >> target/etc/fstab; echo "Added fstab entry for $cachedisk"
    mount "$cachedisk" $cachepath
  ;;
  provcache)
    if [ -h $cachedisk ]; then
        chown -R '19484:109' "$cachepath"
        chmod -R 2775 "$cachepath"
        # "$0" breakpoint
        # echo 'apt-cacher-ng apt-cacher-ng/tunnelenable boolean false' | debconf-set-selections
        in-target --pass-stdout apt-get -qy install apt-cacher-ng
        echo 'Acquire::http { Proxy "http://127.0.0.1:3142"; }' > /etc/apt/apt.conf.d/99proxy
    fi
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
  playprov)
    "$0" provcache
    # "$0" envdump
    # "$0" breakpoint
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

    # "$0" envdump
    # "$0" breakpoint
  ;;
  di-partman-hook)
    echo 'This is the partman hook on stdout'
    echo 'This is the partman hook on stderr' >&2

    # "$0" envdump
    "$0" breakpoint
  ;;
  di-late-hook)
    echo 'This is the late hook on stdout'
    echo 'This is the late hook on stderr' >&2
    cp "$0" /target/root/
    # "$0" playprov

    # "$0" envdump
    # "$0" breakpoint
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


# blkid
# /sbin/blkid

