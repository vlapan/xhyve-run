#!/usr/bin/env bash -e

if [ "Darwin" != "$(uname)" ]; then
	echo "Darwin?"
	exit
fi

XHYVEROOT=/usr/local/share/xhyve
XHYVE=/usr/local/bin/xhyve
if [ ! -x $XHYVE ]; then
	echo "xhyve is required: brew install xhyve --HEAD"
	echo "http://brew.sh/"
	exit
fi

ARPING=/usr/local/sbin/arping
if [ ! -x $ARPING ]; then
	echo "arping is required: brew install arping"
	echo "http://brew.sh/"
	exit
fi

TRUNCATE=/usr/local/bin/truncate
if [ ! -x $TRUNCATE ]; then
	echo "truncate is required: brew install coreutils"
	echo "http://brew.sh/"
	exit
fi

NAME=$1
CMD=$2

if [ "list" = "$NAME" ] && [ "" = "$CMD" ]; then
	ps axuwwwww | grep -v grep | grep xhyve
	exit
fi

if [ "$(whoami)" != "root" ]; then
	echo "run as root: sudo $0 $@"
	exit
fi

if [ -z "$NAME" ]; then
	echo "Usage: $0 name [install|run|start|stop] [-m 512M|--memory=512M] [-c 1|--cpu=1] [-s 2g|--size=2g]"
	echo -e "\t-m 512M|--memory=512M: memory size in MB, may be suffixed with one of K, M, G or T (default 512M)"
	echo -e "\t-c 1|--cpu=1: # cpus (default 1)"
	echo -e "\t-s 2g|--size=2g: default image/disk size (default 2g)"
	echo -e "\t--as=name: save/restore as other name (default, vm name)"
	echo -e "\t--os=bsd: operating system bsd/astra"
	echo
	exit
fi

while [ "$#" -gt 0 ]; do
	case "$1" in
		-m) ARG_MEM="$2"; shift 2;;
		-c) ARG_CPU="$2"; shift 2;;
		-s) ARG_SIZE="$2"; shift 2;;
		-n) ARG_NICE="$2"; shift 2;;

		--memory=*) ARG_MEM="${1#*=}"; shift 1;;
		--cpu=*) ARG_CPU="${1#*=}"; shift 1;;
		--size=*) ARG_SIZE="${1#*=}"; shift 1;;
		--as=*) ARG_AS="${1#*=}"; shift 1;;
		--os=*) ARG_OS="${1#*=}"; shift 1;;
		--iso=*) ARG_ISO="${1#*=}"; shift 1;;
		--memory|--cpu|--size|--as|--os|--iso) echo "$1 requires an argument" >&2; exit 1;;

		-*) echo "unknown option: $1" >&2; exit 1;;
		*) shift 1;;
	esac
done

if [ "$ARG_OS" = "astra" ]; then
	setup_cmd() {
		if [ "$INSTALL" = "YES" ]; then
			VMLINUZ=linux/astra_install/vmlinuz
			USERBOOT=linux/astra_install/initrd.gz
			KERNELENV=$(echo -e "earlyprintk=serial console=ttyS0")
		else
			VMLINUZ=linux/astra_boot/vmlinuz
			USERBOOT=linux/astra_boot/initrd.img
			KERNELENV=$(echo -e "earlyprintk=serial console=ttyS0 rw root=/dev/vda1")
		fi
		if [ ! -f $VMLINUZ ]; then
			echo "astra vmlinuz not found: $VMLINUZ"
			exit
		fi
		if [ ! -f $USERBOOT ]; then
			echo "linux loader not found: $USERBOOT"
			exit
		fi
		NET="-s 2:0,virtio-net"
		IMG_CD="-s 3,ahci-cd,$BOOTVOLUME"
		IMG_HDD="-s 4,virtio-blk,$IMG"
		PCI_DEV="-s 0:0,hostbridge -s 31,lpc"
		LPC_DEV="-l com1,stdio"
		FIRMWARE="-f kexec,$VMLINUZ,$USERBOOT"
	}

	XHYVE="$XHYVE -AwP"
else
	USERBOOT="${XHYVEROOT}/test/userboot.so"
	if [ ! -f $USERBOOT ]; then
		echo "bsd loader not found: $USERBOOT"
		exit
	fi
	KERNELENV=$(echo -e "autoboot_delay=-1") #beastie_disable=YES
	setup_cmd() {
		NET="-s 2:0,virtio-net"
		if [ -f "$VMMACFILE" ]; then
			PMAC=$(cat $VMMACFILE)
			if [ ! -z "$PMAC" ]; then
				#TODO: fix
				NET="$NET,mac=$PMAC"
			fi
		fi
		IMG_CD="-s 3:0,ahci-cd,$BOOTVOLUME"
		IMG_HDD="-s 4:0,virtio-blk,$IMG"
		PCI_DEV="-s 0:0,hostbridge -s 31,lpc"
		LPC_DEV="-l com1,stdio"
		FIRMWARE="-f fbsd,$USERBOOT,$BOOTVOLUME"
	}

	XHYVE="$XHYVE -AwP"
fi


MEM="-m $([ -z "$ARG_MEM" ] && echo '512M' || echo $ARG_MEM)"
SMP="-c $([ -z "$ARG_CPU" ] && echo '1' || echo $ARG_CPU)"
IMG_SIZE="$([ -z "$ARG_SIZE" ] && echo '2g' || echo $ARG_SIZE)"
NICE="$([ -z "$ARG_NICE" ] && echo '0' || echo $ARG_NICE)"


IFACE="bridge100"

mkdir -p img iso

IMG="img/$NAME.img"
UUIDFILE="img/$NAME.uuid"
VMPIDFILE="img/$NAME.pid"
VMMACFILE="img/$NAME.mac"
if [ ! -e "$UUIDFILE" ]; then
	uuidgen > $UUIDFILE
	echo "$(date +%s):VM:$NAME: uuid created: $(cat $UUIDFILE)"
fi
UUID="-U $(cat $UUIDFILE)"


# CMDs
if [ "stop" = "$CMD" ] || [ "kill" = "$CMD" ]; then
	DATE1=$(date +%s)
	if [ ! -f "$VMPIDFILE" ]; then
		echo "$(date +%s):VM:$NAME: no pid file, trying to find by name..."
		VMPID=$(ps axwww | grep "[x]hyve.*$IMG" | cut -f1 -d' ')
		if [ -z "$VMPID" ]; then
			echo "$(date +%s):VM:$NAME: no process found"
			exit
		fi
		echo "$(date +%s):VM:$NAME: process found $PID"
		echo $VMPID > $VMPIDFILE
	fi
	ADD=""
	if [ "kill" = "$CMD" ]; then
		ADD="-9"
	fi
	if /usr/bin/pkill $ADD -F $VMPIDFILE; then
		echo "$(date +%s):VM:$NAME: VM shutting down..."
		VMPID=$(cat $VMPIDFILE)
		while ps axwww $VMPID | grep $VMPID; do
			sleep 1
		done
		DATE2=$(date +%s)
		echo "$(date +%s):VM:$NAME: took $(expr $DATE2 - $DATE1)s: VM stopped"
		rm $VMPIDFILE
	else
		echo "$(date +%s):VM:$NAME: pkill error"
	fi
	exit
elif [ "ip" = "$CMD" ]; then
	MAC=$(cat $VMMACFILE)
	if [ -z "$MAC" ]; then
		echo "$(date +%s):VM:$NAME: error, couldn't get MAC"
		exit 1
	fi
	IP=$($ARPING -i $IFACE -C 1 -r $MAC 2>/dev/null)
	if [ ! -z "$IP" ]; then
		echo "$IP"
	fi
	exit
fi


# Following CMDs require VMs passive state
if test -f "$VMPIDFILE" && /usr/bin/pgrep -qF $VMPIDFILE; then
	echo "$(date +%s):VM:$NAME: active VM process found: $(cat $VMPIDFILE)"
	exit
fi
if ps axwww | grep -q "[x]hyve.*$IMG"; then
	VMPID=$(ps axwww | grep "[x]hyve.*$IMG" | cut -f1 -d' ')
	echo $VMPID > $VMPIDFILE
	echo "$(date +%s):VM:$NAME: active VM process found: $VMPID"
	exit
fi
if [ "install" = "$CMD" ]; then
	# Create image
	if [ ! -f "$IMG" ]; then
		echo "$(date +%s):VM:$NAME: $IMG: creating image: $IMG ($IMG_SIZE)..."
		truncate -s $IMG_SIZE $IMG
		echo "$(date +%s):VM:$NAME: $IMG: image created: $IMG ($IMG_SIZE)"
	else
		IMAGE_SIZE=$(stat -f%z $IMG | awk '{$1=$1/1024/1024/1024;printf "%.0fg\n",$1}')
		echo "$(date +%s):VM:$NAME: image found: $IMAGE_SIZE"
	fi

	if [ ! -z "$ARG_ISO" ]; then
		if [ ! -f $ARG_ISO ]; then
			echo "$(date +%s):VM:$NAME: iso not found: $ARG_ISO"
			exit
		fi
		BOOTVOLUME=$ARG_ISO
	else
		# Check FreeBSD installer image
		FBSD_FTP_ISODIR="ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/ISO-IMAGES"
		FBSD_VERSION=$(/usr/bin/curl -l $FBSD_FTP_ISODIR/ 2>/dev/null | sort -rn | head -1 || echo '')
		if [ -z "$FBSD_VERSION" ]; then
			BOOTVOLUME=$(find iso -type f -print0 | xargs -0 stat -f "%m %N" | sort -rn | head -1 | cut -f2- -d" ")
			if [ -z "$BOOTVOLUME" ]; then
				echo 'Looks like there is no network and no installer images in iso directory, giving up.'
				exit
			fi
		else
			FILE_ISO="FreeBSD-$FBSD_VERSION-RELEASE-amd64-bootonly.iso"
			BOOTVOLUME=iso/$FILE_ISO
			if [ ! -f "$BOOTVOLUME" ]; then
				echo "$(date +%s):VM:$NAME: downloading latest installer..."
				/usr/bin/curl $FBSD_FTP_ISODIR/$FBSD_VERSION/$FILE_ISO.xz | xz -dc > $BOOTVOLUME
				if [ ! -f "$BOOTVOLUME" ]; then
					echo "$(date +%s):VM:$NAME: error: file not found: $BOOTVOLUME: giving up!"
					exit
				fi
				ISO_SIZE=$(stat -f%z $BOOTVOLUME | awk '{$1=$1/1024/1024;printf "%.0fm\n",$1}')
				echo "$(date +%s):VM:$NAME: installer found: $ISO_SIZE"
			fi
		fi
	fi
	INSTALL=YES
	setup_cmd
	$XHYVE $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_CD $IMG_HDD $UUID $FIRMWARE,"$KERNELENV"
elif [ "run" = "$CMD" ]; then
	BOOTVOLUME=$IMG
	setup_cmd
	IMG_HDD="-s 4:0,virtio-blk,$BOOTVOLUME"
	MAC=$($XHYVE -M $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_HDD $UUID $FIRMWARE,"$KERNELENV" | cut -f2 -d' ')
	if [ -z "$MAC" ]; then
		echo "$(date +%s):VM:$NAME: error, couldn't get MAC"
		exit
	fi
	echo $MAC > $VMMACFILE
	set -m
	$XHYVE $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_HDD $UUID $FIRMWARE,"$KERNELENV" &
	VMPID=$!
	echo $VMPID > $VMPIDFILE
	fg
	rm -f $VMPIDFILE
elif [ "start" = "$CMD" ]; then
	DATE1=$(date +%s)
	BOOTVOLUME=$IMG
	setup_cmd
	IMG_HDD="-s 4:0,virtio-blk,$BOOTVOLUME"
	MAC=$($XHYVE -M $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_HDD $UUID $FIRMWARE,"$KERNELENV" | cut -f2 -d' ')
	if [ -z "$MAC" ]; then
		echo "$(date +%s):VM:$NAME: error, couldn't get MAC"
		exit
	fi
	echo $MAC > $VMMACFILE
	nice -n $NICE $XHYVE $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_HDD $UUID $FIRMWARE,"$KERNELENV" > /dev/null 2>&1 &
	VMPID=$!
	echo $VMPID > $VMPIDFILE
	echo "$(date +%s):VM:$NAME: booting..."
	echo "$(date +%s):VM:$NAME: PID: $VMPID"
	echo "$(date +%s):VM:$NAME: MAC: $MAC"
	echo -n "$(date +%s):VM:$NAME: host network..."
	while true; do
		sleep 1
		if ifconfig $IFACE > /dev/null 2>&1; then
			WAN=$(ifconfig $IFACE | grep 'inet ' | cut -d' ' -f2)
			echo " ready"
			echo "$(date +%s):VM:$NAME: WAN: $WAN"
			echo -n "$(date +%s):VM:$NAME: vm network..."
			while true; do
				IP=$($ARPING -i $IFACE -C1 -w1 -r $MAC 2>/dev/null | tail -n1)
				if [ ! -z "$IP" ]; then
					echo " ready"
					echo "$(date +%s):VM:$NAME: IP: $IP"
					DATE2=$(date +%s)
					echo "$(date +%s):VM:$NAME: took $(expr $DATE2 - $DATE1)s: ready"
					exit
				else
					echo -n "."
				fi
			done
		else
			echo -n "."
		fi
	done
elif [ "save" = "$CMD" ]; then
	echo "$(date +%s):VM:$NAME: saving..."
	if [ -z "$ARG_AS" ]; then
		# time gzip -1kfvv $IMG
		time xz -0zkfvv -T 0 $IMG
	else
		OUT=img/$ARG_AS.img.xz
		time xz -0zkfvv -T 0 -c $IMG > $OUT
	fi
	echo "$(date +%s):VM:$NAME: done"
elif [ "restore" = "$CMD" ]; then
	echo "$(date +%s):VM:$NAME: restoring..."
	if [ -z "$ARG_AS" ]; then
		# time gzip -dkf $IMG.gz
		time xz -dkfvv -T 0 $IMG.xz
	else
		IN=img/$ARG_AS.img.xz
		time xz -dkfvv -T 0 -c $IN > $IMG
	fi
	echo "$(date +%s):VM:$NAME: done"
elif [ "mount" = "$CMD" ]; then
	echo "$(date +%s):VM:$NAME: mounting image ($IMG) as block device"
	hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount $IMG
	echo "$(date +%s):VM:$NAME: done"
else
	echo 'Huh?'
fi
