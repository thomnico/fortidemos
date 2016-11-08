#!/bin/bash
# #######
# Copyright (c) 2016 Fortinet All rights reserved
# Author: Nicolas Thomas nthomas_at_fortinet.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
#    * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    * See the License for the specific language governing permissions and
#    * limitations under the License.

set -x
export LC_ALL=C

## avoid warnings about utf-8


is-root()
{
    if [ "$(id -u)" == "0" ]; then
	echo "This script is to be run by your normal user using sudo for root"
	exit 77
    fi
}

control_c()
{
    # run if user hits control-c
    echo -en "\n*** Ouch! Exiting ***\n"
    # can put some cleaning here
    exit $?
}
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT

usage()
{
cat << EOF
    
setup-playground - This script aims to setup you host to be fully ready for playground usage LXD/Docker peros lab

USAGE: -p /dev/sdaX

  The options  must be passed as follows:
  -p,--partition /dev/sdaX   - give a free to use partition 
  -h,--help
  -d , --debug		debug mode 
 Note: actions requires root privileges use sudo 

EOF
exit 0
}

desktop-setup()
{
 #    auto login
     cat << EOF | sudo tee /etc/lightdm/lightdm.conf.d/50-autolog.conf
[SeatDefaults]
autologin-user=$USER
EOF
     export DISPLAY=:0
     gsettings set  org.gnome.Vino enabled true
      #   for broken clients like rdp/Macos
     gsettings set  org.gnome.Vino  require-encryption false
     gsettings set  org.gnome.Vino vnc-password 'Zm9ydGluZXQ='
     gsettings set org.gnome.Vino use-upnp true
}

 is-lxd-ready()
{
    is_ready=0
    # check lxc is on zfs
    (dpkg -l zfsutils-linux >/dev/null ) || is_ready=1;return 0
    ( lxc info |grep "storage:" | grep zfs >/dev/null ) || is_ready=1; return 2
    if [ "$(id -u)" != "0" ]; then
        if [ $is_ready == 0 ]; then
                lxc launch ubuntu:16.04 testme || is_ready=1
                lxc exec testme apt update || is_ready=1
                lxc delete testme --force || echo "cleaned up"
        fi 
    else
        echo "should run this script as a user in the lxd group to check availability"
        return 2
    fi
    return $is_ready
}

lxd-init()
{
    # assume lxd as not been setup correctly 
   
    sudo debconf-set-selections <<< "lxd lxd/bridge-empty-error boolean true"
    sudo debconf-set-selections <<< "lxd lxd/bridge-name string lxdbr0"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv6 string false"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4 string true"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-nat string true"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-dhcp-first string 10.10.10.10"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-address string 10.10.10.1"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-dhcp-last string 10.10.11.253"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-netmask string 21"
    sudo debconf-set-selections <<< "lxd lxd/setup-bridge string true"
    sudo debconf-set-selections <<< "lxd lxd/bridge-ipv4-dhcp-leases string 510"
    sudo cp lxd-bridge /etc/default/
    sudo lxd init --auto   --storage-backend=zfs --storage-create-device=$PARTITION --storage-pool=lxd || exit 2
    sudo dpkg-reconfigure -p high lxd
}


 #check-zfspart()
 #{
    # check the partition is up and type zfs 
     #sudo parted $PARTITION print -m | grep zfs
    
 #}


install-packages()
{
   #  Go passwordless for sudo this is a dev playground DO NOT DO in Prod

    echo "$USER ALL=(ALL) NOPASSWD:ALL" > sudo tee /etc/sudoers.d/99-nopasswd
    # install all the package/ppa sudo kernel setup .

    [ -f /etc/apt/sources.list.d/ubuntu-lxc-ubuntu-lxd-stable-xenial.list ] || sudo add-apt-repository -y ppa:ubuntu-lxc/lxd-stable
    [ -f /etc/apt/sources.list.d/juju-ubuntu-stable-xenial.list ]  || sudo add-apt-repository -y ppa:juju/stable
    sudo apt update
    sudo apt -y install zfsutils-linux lxd virt-manager openvswitch-switch-dpdk juju python-openstackclient python-novaclient python-glanceclient python-neutronclient ubuntu-desktop chromium-browser vino python-pip zile
    [ -f $HOME/.ssh/id_rsa ] ||  ssh-keygen  -t rsa -b 4096 -C "autogenerated key"  -q -P "" -f "$HOME/.ssh/id_rsa"
    sudo systemctl restart lightdm.service
    
}

lxd-prod-configure()
{  
   #  # refer to https://github.com/lxc/lxd/blob/master/doc/production-setup.md
    sudo sed -i '/^root:/d' /etc/subuid /etc/subgid
    echo "root:500000:196608"  | sudo tee -a /etc/subgid /etc/subuid
    cat << EOF | sudo tee -a  /etc/security/limits.conf 
#Add    rules to allow LXD in production type of setups
*  soft  nofile  1048576 #  unset  maximum number of open files
*  hard  nofile  1048576  #unset  maximum number of open files
root  soft  nofile  1048576  #unset  maximum number of open files
root  hard  nofile  1048576  #unset  maximum number of open files
*  soft  memlock  unlimited  #unset  maximum locked-in-memory address space (KB)
*  hard  memlock  unlimited #unset  maximum locked-in-memory address space (KB)
EOF

cat << EOF  | sudo tee /etc/sysctl.d/90-lxd.conf 
#Add rules to allow LXD in production type of setups
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144


net.core.netdev_max_backlog=182757

EOF
cat << EOF | sudo tee -a  /etc/sysctl.conf
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
EOF
sudo rm /usr/lib/sysctl.d/juju-2.0.conf
#To see what is going on
sudo sysctl --system

}
   
OPTS=$(getopt -o hdp: --long help,debug,partition: \
     -n 'setup-playground' -- "$@")

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$OPTS': they are essential!
eval set -- "$OPTS"
MAIN=1
while true ; do
        case "$1" in
            -h|--help) usage ; exit 0 ;;
	    -d|--debug) set -x; shift ;;
            -p|--partition) PARTITION="$2" ; MAIN=0; shift 2 ;;
            --) break ;;
            *) usage; exit 1 ;;
        esac
done

if [ "$MAIN" == "0" ]; then
   is-root
   install-packages
   desktop-setup
   is-lxd-ready || lxd-init
   lxd-prod-configure
   echo "You are all set it is highly recommended to restart now"
fi