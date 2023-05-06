#! /bin/bash

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
