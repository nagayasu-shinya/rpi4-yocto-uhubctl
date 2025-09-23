FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://ethernet.config"

do_install:append() {
    install -d ${D}${localstatedir}/lib/connman
    install -m 0644 ${WORKDIR}/ethernet.config ${D}${localstatedir}/lib/connman/
}

FILES:${PN} += "${localstatedir}/lib/connman/ethernet.config"
