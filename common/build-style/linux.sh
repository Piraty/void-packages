#
# This helper is for templates building the linux kernel.
#

do_configure() {
	cross=
	[ -n "$CROSS_BUILD" ] && cross="CROSS_COMPILE=${XBPS_CROSS_TRIPLET}-"

	if [ -n "$kernel_config_target" ]; then
		msg_normal "Config target: '$kernel_config_target'.\n"
	elif [ -f ./.config ]; then
		msg_normal "Found .config, using 'oldconfig'.\n"
		kernel_config_target=oldconfig
	else
		msg_normal "Defaulting to 'allmodconfig'.\n"
		kernel_config_target=allmodconfig
	fi

	# Remove .git directory, otherwise scripts/setkernelversion.sh
	# modifies KERNELRELEASE and appends + to it.
	rm -rf .git

	# Always use our revision to CONFIG_LOCALVERSION to match our pkg version.
	sed -i -e "s|^\(CONFIG_LOCALVERSION=\).*|\1\"_${revision}\"|" .config

	make $makejobs ARCH=$kernel_arch $cross $kernel_config_target
}

do_build() {
	cross=
	[ -n "$CROSS_BUILD" ] && cross="CROSS_COMPILE=${XBPS_CROSS_TRIPLET}-"

	extraversion=
	[ -n "$kernel_patchver" ] && extraversion="EXTRAVERSION=${kernel_patchver}"

	case "$kernel_arch" in
		arm) target="zImage modules dtbs";;
		arm64) target="Image modules dtbs";;
		mips) target="uImage modules dtbs";;
		powerpc) target="zImage modules";;
		x86) target="bzImage modules";;
	esac

	export LDFLAGS= #FIXME: is this still needed? maybe some arch only?
	make $makejobs ARCH=$kernel_arch $cross $extraversion prepare
	make $makejobs ARCH=$kernel_arch $cross $extraversion $target
}

do_check() {
	:
}

#TODO
#	* clearly separate kernel / header handling
do_install() {
	: ${kernel_version:="${version}_${revision}"}

	cross=
	[ -n "$CROSS_BUILD" ] && cross="CROSS_COMPILE=${XBPS_CROSS_TRIPLET}-"

	hdrdest=${DESTDIR}/usr/src/kernel-headers-${kernel_version}

	# Install kernel, firmware and modules
	make ${makejobs} ARCH=${kernel_subarch:-$kernel_arch} INSTALL_MOD_PATH=${DESTDIR} ${_cross} modules_install

	case "$kernel_arch" in
		x86)
			vinstall arch/x86/boot/bzImage 644 boot vmlinuz-${kernel_version}
			;;
		arm)
			vinstall arch/arm/boot/zImage 644 boot
			make ${makejobs} ARCH=${kernel_subarch:-$kernel_arch} INSTALL_DTBS_PATH=${DESTDIR}/boot/dtbs/dtbs-${kernel_version} ${_cross} dtbs_install
			;;
		arm64)
			vinstall arch/arm64/boot/Image 644 boot vmlinux-${kernel_version}
			make ${makejobs} ARCH=${kernel_subarch:-$kernel_arch} INSTALL_DTBS_PATH=${DESTDIR}/boot/dtbs/dtbs-${kernel_version} ${_cross} dtbs_install
			;;
		powerpc)
			# zImage on powerpc is useless as it won't load initramfs
			# raw vmlinux is huge, and this is nostrip, so do it manually
			vinstall vmlinux 644 boot vmlinux-${kernel_version}
			/usr/bin/$STRIP ${DESTDIR}/boot/vmlinux-${kernel_version}
			;;
		mips)
			vinstall arch/mips/boot/uImage.bin 644 boot uImage-${kernel_version}
			make ${makejobs} ARCH=${kernel_subarch:-$kernel_arch} INSTALL_DTBS_PATH=${DESTDIR}/boot/dtbs/dtbs-${kernel_version} ${_cross} dtbs_install
			;;
	esac
	vinstall .config 644 boot config-${kernel_version}
	vinstall System.map 644 boot System.map-${kernel_version}

	# Run depmod after compressing modules.
	vsed -i '2iexit 0' scripts/depmod.sh

	### HEADERS ??

	# Switch to /usr.
	vmkdir usr
	mv ${DESTDIR}/lib ${DESTDIR}/usr

	cd ${DESTDIR}/usr/lib/modules/${kernel_version}
	rm -f source build
	ln -sf ../../../src/${sourcepkg}-headers-${kernel_version} build

	cd ${wrksrc}
	# Install required headers to build external modules
	install -Dm644 Makefile ${hdrdest}/Makefile
	install -Dm644 kernel/Makefile ${hdrdest}/kernel/Makefile
	install -Dm644 .config ${hdrdest}/.config
	for file in $(find . -name Kconfig\*); do
		mkdir -p ${hdrdest}/$(dirname $file)
		install -Dm644 $file ${hdrdest}/${file}
	done
	for file in $(find arch/${kernel_arch} -name module.lds -o -name Kbuild.platforms -o -name Platform); do
		mkdir -p ${hdrdest}/$(dirname $file)
		install -Dm644 $file ${hdrdest}/${file}
	done

	mkdir -p ${hdrdest}/include
	for i in acpi asm-generic clocksource config crypto drm dt-bindings \
		generated linux math-emu media net pcmcia scsi sound trace uapi vdso \
		video xen; do
		[ -d include/$i ] && cp -a include/$i ${hdrdest}/include
	done

	# Remove helper binaries built for host. if generated files from the scripts/
	# directory need to be included, they need to be copied to ${hdrdest} before
	# this step
	if [ "$CROSS_BUILD" ]; then
		make ${makejobs} ARCH=${kernel_subarch:-$kernel_arch} _mrproper_scripts
		#FIXME: crossbuild in this template instead of building them on the target device during dkms hook
	fi

	# copy arch includes for external modules
	mkdir -p ${hdrdest}/arch/${kernel_arch}/kernel
	cp arch/${kernel_arch}/Makefile ${hdrdest}/arch/${kernel_arch}
	cp -a arch/${kernel_arch}/include ${hdrdest}/arch/${kernel_arch}
	if [ "$kernel_subarch" = "i386" ]; then
		mkdir -p ${hdrdest}/arch/x86
		cp arch/x86/Makefile_32.cpu ${hdrdest}/arch/x86
	fi
	if [ "$kernel_arch" = "x86" ]; then
		mkdir -p ${hdrdest}/arch/x86/kernel
		cp arch/x86/kernel/asm-offsets.s ${hdrdest}/arch/x86/kernel
	elif [ "$kernel_arch" = "arm64" ]; then
		mkdir -p ${hdrdest}/arch/arm64/kernel
		cp -a arch/arm64/kernel/vdso ${hdrdest}/arch/arm64/kernel/
	fi

	# Copy files necessary for later builds, like nvidia and vmware
	cp Module.symvers ${hdrdest}
	cp -a scripts ${hdrdest}
	mkdir -p ${hdrdest}/security/selinux
	cp -a security/selinux/include ${hdrdest}/security/selinux
	mkdir -p ${hdrdest}/tools/include
	cp -a tools/include/tools ${hdrdest}/tools/include
	if [ -d "arch/${kernel_arch}/tools" ]; then
		cp -a arch/${kernel_arch}/tools ${hdrdest}/arch/${kernel_arch}
	fi

	# add headers for lirc package
	# pci
	for i in bt8xx cx88 saa7134; do
		mkdir -p ${hdrdest}/drivers/media/pci/${i}
		cp -a drivers/media/pci/${i}/*.h ${hdrdest}/drivers/media/pci/${i}
	done
	# usb
	for i in cpia2 em28xx pwc; do
		mkdir -p ${hdrdest}/drivers/media/usb/${i}
		cp -a drivers/media/usb/${i}/*.h ${hdrdest}/drivers/media/usb/${i}
	done
	# i2c
	mkdir -p ${hdrdest}/drivers/media/i2c
	cp drivers/media/i2c/*.h ${hdrdest}/drivers/media/i2c
	for i in cx25840; do
		mkdir -p ${hdrdest}/drivers/media/i2c/${i}
		cp -a drivers/media/i2c/${i}/*.h ${hdrdest}/drivers/media/i2c/${i}
	done

	if [ -f "Documentation/DocBook/Makefile" ]; then
		install -Dm644 Documentation/DocBook/Makefile \
			${hdrdest}/Documentation/DocBook/Makefile
	fi

	# Add md headers
	mkdir -p ${hdrdest}/drivers/md
	cp drivers/md/*.h ${hdrdest}/drivers/md

	# Add inotify.h
	mkdir -p ${hdrdest}/include/linux
	cp include/linux/inotify.h ${hdrdest}/include/linux

	# Add wireless headers
	mkdir -p ${hdrdest}/net/mac80211/
	cp net/mac80211/*.h ${hdrdest}/net/mac80211

	# add dvb headers for external modules
	mkdir -p ${hdrdest}/include/config/dvb/
	cp include/config/dvb/*.h ${hdrdest}/include/config/dvb/

	# add dvb headers for http://mcentral.de/hg/~mrec/em28xx-new
	mkdir -p ${hdrdest}/drivers/media/dvb-frontends
	cp drivers/media/dvb-frontends/lgdt330x.h \
		${hdrdest}/drivers/media/dvb-frontends/
	cp drivers/media/i2c/msp3400-driver.h ${hdrdest}/drivers/media/i2c/

	# add dvb headers
	mkdir -p ${hdrdest}/drivers/media/usb/dvb-usb
	cp drivers/media/usb/dvb-usb/*.h ${hdrdest}/drivers/media/usb/dvb-usb/
	mkdir -p ${hdrdest}/drivers/media/dvb-frontends
	cp drivers/media/dvb-frontends/*.h ${hdrdest}/drivers/media/dvb-frontends/
	mkdir -p ${hdrdest}/drivers/media/tuners
	cp drivers/media/tuners/*.h ${hdrdest}/drivers/media/tuners/

	# Add xfs and shmem for aufs building
	mkdir -p ${hdrdest}/fs/xfs/libxfs
	mkdir -p ${hdrdest}/mm
	cp fs/xfs/libxfs/xfs_sb.h ${hdrdest}/fs/xfs/libxfs/xfs_sb.h

	# Add objtool binary, needed to build external modules with dkms
	case "$XBPS_TARGET_MACHINE" in
		x86_64*)
			mkdir -p ${hdrdest}/tools/objtool
			cp tools/objtool/objtool ${hdrdest}/tools/objtool
			;;
	esac

	# Remove unneeded architectures
	mkdir -p arch-backup
	cp -r ${hdrdest}/arch/${kernel_arch} ${hdrdest}/arch/Kconfig arch-backup/
	rm -rf ${hdrdest}/arch
	mv arch-backup ${hdrdest}/arch
	# Keep arch/x86/ras/Kconfig as it is needed by drivers/ras/Kconfig
	mkdir -p ${hdrdest}/arch/x86/ras
	cp -a arch/x86/ras/Kconfig ${hdrdest}/arch/x86/ras/Kconfig

	# clean headers of build artifacts
	find ${hdrdest} -name '*.o' -delete
	find ${hdrdest} -name '*.cmd' -delete
}

do_check() {
	:
}
