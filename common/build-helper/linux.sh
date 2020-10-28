# This build-helper helps to determine a few things required
# to build the linux kernel.

#FIXME: get rid of subarch, possibly deprecated since linux3. dotconfigs define the subarch
kernel_arch=
kernel_arch_subarch=
case "$XBPS_TARGET_MACHINE" in
	i686*) kernel_arch=x86 ; kernel_subarch=i386;;
	x86_64*) kernel_arch=x86 ; kernel_subarch=x86_64;;
	arm*) kernel_arch=arm;;
	aarch64*) kernel_arch=arm64;;
	ppc64le*) kernel_arch=powerpc; kernel_subarch=ppc64le;;
	ppc64*) kernel_arch=powerpc; kernel_subarch=ppc64;;
	ppc*) kernel_arch=powerpc;;
	mips*) kernel_arch=mips;;
esac
