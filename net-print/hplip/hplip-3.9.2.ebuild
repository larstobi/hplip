# Copyright 1999-2009 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/net-print/hplip/hplip-2.8.7.ebuild,v 1.2 2009/03/14 19:04:39 armin76 Exp $

inherit eutils linux-info python

DESCRIPTION="HP Linux Imaging and Printing System. Includes net-print/hpijs, scanner drivers and service tools."
HOMEPAGE="http://hplipopensource.com/"
SRC_URI="mirror://sourceforge/hplip/${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~ppc ~ppc64 ~x86"

IUSE="cupsddk dbus doc fax gtk minimal parport ppds qt3 qt4 scanner snmp"

DEPEND="!net-print/hpijs
	!net-print/hpoj
	virtual/ghostscript
	>=media-libs/jpeg-6b
	>=net-print/foomatic-filters-3.0.20080507
	!minimal? (
		>=net-print/cups-1.2
		dev-libs/libusb
		cupsddk? ( net-print/cupsddk )
		dbus? ( >=sys-apps/dbus-1.0.0 )
		scanner? ( >=media-gfx/sane-backends-1.0.19-r1 )
		snmp? (
			net-analyzer/net-snmp
			dev-libs/openssl
		)
	)"

RDEPEND="${DEPEND}
	!minimal? (
		!<sys-fs/udev-114
		scanner? (
			dev-python/imaging
			gtk? ( >=media-gfx/xsane-0.89 )
			!gtk? ( >=media-gfx/sane-frontends-1.0.9 )
		)
		qt4? ( !qt3? (
			dev-python/PyQt4
			dbus? ( >=dev-python/dbus-python-0.80 )
			fax? ( dev-python/reportlab )
		) )
		qt3? (
			>=dev-python/PyQt-3.14
			dev-python/ctypes
			dbus? ( >=dev-python/dbus-python-0.80 )
			fax? ( dev-python/reportlab )
		)
	)"

CONFIG_CHECK="PARPORT PPDEV"
ERROR_PARPORT="Please make sure parallel port support is enabled in your kernel (PARPORT and PPDEV)."

pkg_setup() {
	! use qt3 && ! use qt4 && ewarn "You need USE=qt3 (recommended) or USE=qt4 for the hplip GUI."

	use scanner && ! use gtk && ewarn "You need USE=gtk for the scanner GUI."

	if ! use ppds && ! use cupsddk; then
		ewarn "Installing neither static (USE=-ppds) nor dynamic (USE=-cupsddk) PPD files,"
		ewarn "which is probably not what you want. You will almost certainly not be able to "
		ewarn "print (recommended: USE=\"cupsddk -ppds\")."
	fi

	if use minimal ; then
		ewarn "Installing hpijs driver only, make sure you know what you are doing."
	else
		use parport && linux-info_pkg_setup
	fi
}

src_unpack() {
	unpack ${A}
	cd "${S}"

	sed -i -e "s:\$(doc_DATA)::" Makefile.in || die "Patching Makefile.in failed"
	sed -i -e "s/'skipstone']/'skipstone', 'epiphany']/" \
		-e "s/'skipstone': ''}/'skipstone': '', 'epiphany': '--new-window'}/" \
		base/utils.py  || die "Patching base/utils.py failed"

	# bug 98428
	sed -i -e "s:/usr/bin/env python:/usr/bin/python:g" hpssd.py || die "Patching hpssd.py failed"

	# Force recognition of Gentoo distro by hp-check
	sed -i \
		-e "s:file('/etc/issue', 'r').read():'Gentoo':" \
		installer/core_install.py || die "sed core_install.py"

	# Replace udev rules, see bug #197726.
	rm data/rules/55-hpmud.rules
	cp "${FILESDIR}"/70-hpmud.rules data/rules
	sed -i -e "s/55-hpmud.rules/70-hpmud.rules/g" Makefile.* */*.html || die "sed failed"

	# Use system foomatic-rip instead of foomatic-rip-hplip
	sed -i -e 's/foomatic-rip-hplip/foomatic-rip/' ppd/*.ppd || die "sed failed"

	# Qt4 is still undocumented by upstream, so use with caution
	local QT_VER
	use qt4 && QT_VER="4"
	use qt3 && QT_VER="3"
	sed -i \
		-e "s/%s --force-startup/%s --force-startup --qt${QT_VER}/" \
		-e "s/'--force-startup'/'--force-startup', '--qt${QT_VER}'/" \
		base/device.py || die "sed failed"
	sed -i \
		-e "s/Exec=hp-systray/Exec=hp-systray --qt${QT_VER}/" \
		hplip-systray.desktop.in || die "sed failed"
}

src_compile() {
	if use qt3 || use qt4 ; then
		local GUI_BUILD="--enable-gui-build"
	else
		local GUI_BUILD="--disable-gui-build"
	fi

	econf \
		--disable-dependency-tracking \
		--disable-cups11-build \
		--with-cupsbackenddir=$(cups-config --serverbin)/backend \
		--with-cupsfilterdir=$(cups-config --serverbin)/filter \
		--disable-foomatic-rip-hplip-install \
		${GUI_BUILD} \
		$(use_enable doc doc-build) \
		$(use_enable cupsddk foomatic-drv-install) \
		$(use_enable dbus dbus-build) \
		$(use_enable fax fax-build) \
		$(use_enable minimal hpijs-only-build) \
		$(use_enable parport pp-build) \
		$(use_enable ppds foomatic-ppd-install) \
		$(use_enable scanner scan-build) \
		$(use_enable snmp network-build) \
		|| die "econf failed"
	emake || die "Compilation failed"
}

src_install() {
	emake -j1 DESTDIR="${D}" install || die "emake install failed"
	rm -f "${D}"/etc/sane.d/dll.conf

	# bug 106035
	use qt3 || use qt4 || rm -Rf "${D}"/usr/share/applications

	use minimal && rm -rf "${D}"/usr/lib
}

pkg_preinst() {
	# avoid collisions with cups-1.2 compat symlinks
	if [ -e "${ROOT}"/usr/lib/cups/backend/hp ] && [ -e "${ROOT}"/usr/libexec/cups/backend/hp ]; then
		rm -f "${ROOT}"/usr/libexec/cups/backend/hp{,fax};
	fi
}

pkg_postinst() {
	python_mod_optimize /usr/share/${PN}

	elog "You should run hp-setup as root if you are installing hplip for the first time, and may also"
	elog "need to run it if you are upgrading from an earlier version."
	elog
	elog "If your device is connected using USB, users will need to be in the lp group to access it."
	elog
	elog "This release doesn't use an init script anymore, so you should probably do a"
	elog "'rc-update del hplip' if you are updating from an old version."
}

pkg_postrm() {
	python_mod_cleanup /usr/share/${PN}
}
