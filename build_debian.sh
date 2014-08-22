#!/bin/bash -e

# Created by: 
usage() {
	cat <<EOF

Usage: $0 [options]

This script is intended to build CentOS images for docker style containers of any architecture and version, available.

Options:
  -h	This output.
  -v	Debian version (default wheezy)
  -a	Debian architecture (default amd64)
  -t	Base temp build directory. (default mktemp -d)
  -p	Install additional packages, one per flag.
  	(default: apt-get, tar, which)
  -m	Alternative mirror to use. (default: http://ftp.uk.debian.org/debian/)
  	This will not use a set version or arch, only mirror.

EOF
}

pkgs="base, build-essential, apt-get, tar, wget"

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
	version="wheezy"
fi
if [[ -z $arch ]]; then
	arch="amd64"
fi
if [[ -z $tempdir ]]; then
	tmpdir=$( mktemp -d )
	trap "echo removing ${tmpdir}; rm -rf ${tmpdir}" EXIT
fi
if [[ -z $mirror ]]; then
	mirror="http://ftp.uk.debian.org/debian/"
fi
ver=$( echo $version | sed s/[.]// )

## requires running as root because filesystem package won't install otherwise,
## giving a cryptic error about /proc, cpio, and utime.  As a result, /tmp
## doesn't exist.
[ $( id -u ) -eq 0 ] || { echo "must be root"; exit 1; }

## Download and build base image
debootstrap ${options} --arch=${arch} ${ver} ${tmpdir} ${mirror}

## Taken from http://github.com/docker/docker/blob/master/contrib/mkkimage/debootstrap

# prevent init scripts from running during install/update
echo >&2 "+ echo exit 101 > '$tmpdir/usr/sbin/policy-rc.d'"

cat > "$tmpdir/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh

# For most Docker users, "apt-get install" only happens during "docker build",
# where starting services doesn't work and often fails in humorous ways. This
# prevents those failures by stopping the services from attempting to start.

exit 101
EOF

chmod +x "$tmpdir/usr/sbin/policy-rc.d"

# prevent upstart scripts from running during install/update
(
        set -x
	chroot "$tmpdir" dpkg-divert --local --rename --add /sbin/initctl
	cp -a "$tmpdir/usr/sbin/policy-rc.d" "$tmpdir/sbin/initctl"
	sed -i 's/^exit.*/exit 0/' "$tmpdir/sbin/initctl"
)

# make sure we're fully up-to-date
(
	set -x
	chroot "$tmpdir" apt-get update
	chroot "$tmpdir" apt-get dist-upgrade -y
)

# shrink a little, since apt makes us cache-fat (wheezy: ~157.5MB vs ~120MB)
(
	set -x
	chroot "$tmpdir" apt-get clean
)

# force non-caching of dpkg/apt
echo 'force-unsafe-io' | sudo tee ${tmpdir}/etc/dpkg/dpkg.cfg.d/02apt-speedup > /dev/null

# delete all the apt list files since they're big and get stale quickly
rm -rf "$tmpdir/var/lib/apt/lists"/*

## xz gives the smallest size by far, compared to bzip2 and gzip, by like 50%!
(
	cd ${tmpdir}
	tar --numeric-owner -cf . | xz > debian-${ver}-${arch}.tar.xz
)

mv ${tmpdir}/debian-${ver}-${arch}.tar.xz ./
