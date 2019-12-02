#!/bin/bash -x 

#
# Copyright (C) 2019 Canonical
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Colin Ian King <colin.king@canonical.com>
#

HERE=${PWD}
NUMCPUS=$(nproc)
#REPO=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux
REPO=https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next
DEBIAN_RELEASE=buster

set_config()
{
	sed -i 's/# CONFIG_KCOV is not set/CONFIG_KCOV=y/' .config
	sed -i 's/# CONFIG_DEBUG_INFO is not set/CONFIG_DEBUG_INFO=y/' .config
	sed -i 's/# CCONFIG_KASAN is not set/CONFIG_KASAN=y/' .config
	sed -i 's/# CONFIG_KASAN_INLINE is not set/CONFIG_KASAN_INLINE=y/' .config
	sed -i 's/# CONFIG_CONFIGFS_FS is not set/CONFIG_CONFIGFS_FS=y/' .config
	sed -i 's/# CONFIG_SECURITYFS is not set/CONFIG_SECURITYFS=y/' .config
	sed -i 's/# CONFIG_FAULT_INJECTION is not set/CONFIG_FAULT_INJECTION=y/' .config
	sed -i 's/# CONFIG_FAULT_INJECTION_DEBUG_FS is not set/CONFIG_FAULT_INJECTION_DEBUG_FS=y/' .config
	sed -i 's/# CONFIG_DEBUG_KMEMLEAK is not set/CONFIG_DEBUG_KMEMLEAK=y/' .config
	sed -i 's/# CONFIG_FAILSLAB is not set/CONFIG_FAILSLAB=y/' .config
	sed -i 's/# CONFIG_KCOV_ENABLE_COMPARISONS is not set/CONFIG_KCOV_ENABLE_COMPARISONS=y/' .config
}


sudo apt install debootstrap -y
sudo apt install golang-go -y
sudo apt install qemu-kvm
if ! id -nG "$USER" | grep -qw "kvm" ; then
	sudo addgroup $USER kvm
fi

if [ ! -f $HOME/go/src/github.com/google/syzkaller/bin/syz-manager ]; then
	mkdir -p $HOME/go
	export GOPATH=$HOME/go
	export PATH=$GOPATH:$PATH
	go get -u -d github.com/google/syzkaller/...
	cd $HOME/go/src/github.com/google/syzkaller/
	make -j ${NUMCPUS}
	cd ${HERE}
fi

mkdir -p $HOME/go/src/github.com/google/syzkaller/workdir

if [ ! -d linux ]; then
	git clone ${REPO} kernel --depth 1
else
	git pull
fi

if [ ! -f kernel/vmlinux ]; then
	cd kernel
	make defconfig
	make kvmconfig
	set_config
	yes "" | make oldconfig
	set_config
	yes "Y" | make -j ${NUMCPUS}
	cd ${HERE}
fi

if [ ! -f image/buster.img ]; then
	mkdir image
	cd image
	wget https://raw.githubusercontent.com/google/syzkaller/master/tools/create-image.sh -O create-image.sh
	chmod +x create-image.sh
	chmod +x ./create-image.sh
	./create-image.sh --distribution ${DEBIAN_RELEASE}
	cd ..
fi

#
#  Autogenerate config file
#
cat << EOF > my.cfg
{
	"target": "linux/amd64",
	"http": "127.0.0.1:56741",
	"workdir": "HOME/go/src/github.com/google/syzkaller/workdir",
	"kernel_obj": "HERE/kernel",
	"image": "HERE/image/DEBIAN_RELEASE.img",
	"sshkey": "HERE/image/DEBIAN_RELEASE.id_rsa",
	"syzkaller": "HOME/go/src/github.com/google/syzkaller",
	"procs": 8,
	"type": "qemu",
	"vm": {
		"count": NUMCPUS,
		"kernel": "HERE/kernel/arch/x86/boot/bzImage",
		"cpu": 2,
		"mem": 2048
	}
}
EOF
sed -i "s@DEBIAN_RELEASE@$DEBIAN_RELEASE@" ${HERE}/my.cfg
sed -i "s@HOME@$HOME@" ${HERE}/my.cfg
sed -i "s@HERE@$HERE@" ${HERE}/my.cfg
sed -i "s@NUMCPUS@$NUMCPUS@" ${HERE}/my.cfg

#
#  Adding the user to a new kvm group means we need
#  to use sg to be able to run a process user the
#  group privileges
# 
sudo sg kvm -c "cd $HOME/go/src/github.com/google/syzkaller; ./bin/syz-manager -config=${HERE}/my.cfg"
cd $HERE
