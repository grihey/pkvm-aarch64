#!/bin/bash

#
# Tested on ubuntu 20+. You need to have qemu-user-static and binfmt-support
# installed.
#

TOOLDIR=$BASE_DIR/buildtools
QEMU_USER=`which qemu-aarch64-static`

#
# Default: dynamic, opengl, spice, virgl, hybris
#

UBUNTU_BASE=http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-arm64.tar.gz
PKGLIST=`cat $BASE_DIR/scripts/package.list.22`

#
# Note: cross-compilation is also possible, these can be passed through.
#
unset CC
unset LD
unset CXX
unset AR
unset CPP
unset CROSS_COMPILE
unset CFLAGS
unset LDFLAGS
unset ASFLAGS
unset INCLUDES
unset WARNINGS
unset DEFINES

export PATH=$TOOLDIR/bin:$TOOLDIR/usr/bin:/bin:/usr/bin
export CHROOTDIR=$BASE_DIR/oss/ubuntu
export UBUNTUTEMPLATE=$BASE_DIR/oss/ubuntu-template

NJOBS_MAX=8
NJOBS=`nproc`
REPO=`which repo`

if [ $NJOBS -gt $NJOBS_MAX ];then
	NJOBS=$NJOBS_MAX
fi

set -e

do_unmount()
{
	if [[ $(findmnt -M "$1") ]]; then
		sudo umount $1
		if [ $? -ne 0 ]; then
			echo "ERROR: failed to umount $1"
			exit 1
		fi
	fi
}

do_unmount_all()
{
	[ -n "$LEAVE_MOUNTS" ] && echo "leaving bind mounts in place." && exit 0

	echo "Unmount all binding dirs"
	do_unmount $CHROOTDIR/build/crosvm
	do_unmount $CHROOTDIR/proc
	do_unmount $CHROOTDIR/dev
}

do_clean()
{
	do_unmount_all
	cd $BASE_DIR/crosvm; sudo git clean -xfd || true
}

do_distclean()
{
	do_unmount_all
	cd $BASE_DIR/crosvm; sudo git clean -xfd || true
	sudo rm -rf $CHROOTDIR
}

do_sysroot()
{
	mkdir -p $CHROOTDIR/build
	if [ -e $CHROOTDIR/bin/bash ]; then
		sudo mount --bind /dev $CHROOTDIR/dev
		sudo mount -t proc none $CHROOTDIR/proc
		return;
	fi

	sudo tar -C $UBUNTUTEMPLATE -cf - ./|tar -C $CHROOTDIR -xf -
	cd $CHROOTDIR
	sudo mount --bind /dev $CHROOTDIR/dev
	sudo mount -t proc none $CHROOTDIR/proc
}

do_crosvm()
{
	#
	# Build always
	#
	mkdir -p $CHROOTDIR/build/crosvm
	sudo mount --bind $BASE_DIR/crosvm $CHROOTDIR/build/crosvm
	cd $CHROOTDIR/build/crosvm

	sudo -E chroot $CHROOTDIR sh -c "cd /build/crosvm; cargo build --verbose -j $NJOBS --features=gdb; install target/debug/crosvm /usr/bin"
}


if [[ "$#" -eq 1 ]] && [[ "$1" == "clean" ]]; then
	do_clean
        exit 0
fi
if [[ "$#" -eq 1 ]] && [[ "$1" == "distclean" ]]; then
	do_distclean
        exit 0
fi

trap do_unmount_all SIGHUP SIGINT SIGTERM EXIT

do_sysroot
do_crosvm
cd $BASE_DIR

echo "All ok!"
