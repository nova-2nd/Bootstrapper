# Debian preseeding

<https://hands.com/d-i/>
<https://wiki.debian.org/DebianInstaller/Preseed>
<https://d-i.debian.org/doc/installation-guide/en.amd64/apbs03.html>
<https://preseed.debian.net/debian-preseed/>
<https://www.debian.org/releases/stable/i386/ch04s03.en.html>
<https://wiki.debian.org/Installation+Archive+USBStick>
<https://wiki.debian.org/tasksel>

## consider inclusion

- debconf-utils
- whois
- apt install $(tasksel --task-packages standard)

## Ansible provisioning

apt install python3-venv
python3 -m venv /var/lib/ansible
source /var/lib/ansible/bin/activate
pip install -U pip setuptools wheel
pip install ansible
deactivate
ln -s /var/lib/ansible/bin/ansible /usr/local/sbin/ansible

## user provision

apt install sudo
adduser xxxx
usermod -aG sudo xxxx

## provision desktop

apt install task-kde-desktop
