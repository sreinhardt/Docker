#!/bin/bash -e

# Created by: 
usage() {
	cat <<EOF

Usage: $0 [options]

This script is intended to build ArchLinux images for docker style containers of any architecture and version, available. This is intended to work with AUR febootstrap.

Options:
  -h	This output.
  -v	ArchLinux version (default 6.5)
  -a	ArchLinux architecture (default x86_64)
  -t	Base temp build directory. (default mktemp -d)
  -p	Install additional packages, one per flag.
  	(default: base)
  -m	Alternative mirror to use. (default: )
  	This will not use a set version or arch, only mirror.

EOF
}

pkgs="-i base"

## Handle cli arguments
while getopts "hv:a:t:p:" opt
	do
	case $opt in
		h)
			usage
			exit 0
			;;
		v)
			version="$OPTARG"
			;;
		a)
			arch="$OPTARG"
			;;
		t)
			tempdir=$( mktemp -p "$OPTARG" )
			trap "echo removing ${tmpdir}; rm -rf ${tmpdir}" EXIT
			;;
		p)
			pkgs="$pkgs -i $OPTARG"
			;;
		m)
			mirror="$OPTARG"
			;;
		?)
			usage
			exit 1
			;;
	esac
done

## Set defaults if args were not provided
if [[ -z $version ]]; then
	version="6.5"
fi
if [[ -z $arch ]]; then
	arch="x86_64"
fi
if [[ -z $tempdir ]]; then
	tmpdir=$( mktemp -d )
	trap "echo removing ${tmpdir}; rm -rf ${tmpdir}" EXIT
fi
if [[ -z $mirror ]]; then
	mirror="http://mirrors.mit.edu/centos/$version/os/$arch/"
fi
ver=$( echo $version | sed s/[.]// )

## requires running as root because filesystem package won't install otherwise,
## giving a cryptic error about /proc, cpio, and utime.  As a result, /tmp
## doesn't exist.
[ $( id -u ) -eq 0 ] || { echo "must be root"; exit 1; }

## Download and build base image
febootstrap $pkgs centos$ver ${tmpdir} $mirror

## Enable networking service
febootstrap-run ${tmpdir} -- sh -c 'echo "NETWORKING=yes" > /etc/sysconfig/network'

## set timezone of container to UTC
febootstrap-run ${tmpdir} -- ln -f /usr/share/zoneinfo/Etc/UTC /etc/localtime

## Clean pacman junk
febootstrap-run ${tmpdir} -- pacman -clean

## xz gives the smallest size by far, compared to bzip2 and gzip, by like 50%!
febootstrap-run ${tmpdir} -- tar -cf - . | xz > arch$ver-$arch.tar.xz
