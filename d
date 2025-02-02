#!/bin/sh
# wrapper for running the app

DEV=kiwi
BUILD_DIR=../build
PROG=${BUILD_DIR}/kiwi.bin

CMD=$(basename $0)
case ${CMD} in
	"k"|"kiwi")
		ARGS="+gps $*"
		;;
	"ng"|"n")
		ARGS="-gps $*"
		;;
	"g")
		ARGS="+gps -stats 1 $*"
		;;
	"d")
		ARGS="-gps -leds -debug $*"
		;;
esac

# hack to see if we're running on a BBB
if test ! -f /etc/dogtag; then
	${PROG} ${ARGS}
	exit 0
fi

RPI=$(grep -q -s "Raspberry Pi" /boot/issue.txt; echo $?)
BBAI=$(grep -q -s "BeagleBoard" /etc/dogtag; echo $?)

if [ "x${BBAI}" = "xtrue" ] ; then
    SBC="BBAI"
	DEBIAN=9
	USE_SPIDEV=1
    USE_SPI="USE_SPIDEV"
elif [ "x${RPI}" = "xtrue" ] ; then
    SBC="RPI"
	DEBIAN=10
	USE_SPIDEV=1
    USE_SPI="USE_SPIDEV"
else
    # BBG/BBB
    # Debian 7, PIO: load our cape-bone-S overlay via echo > slots
    # Debian 7, SPIDEV: BB-SPIDEV0 loaded via echo > slots
    # Debian 8, PIO: load our cape-bone-S overlay via echo > slots
    # Debian 8, SPIDEV: Bug: BB-SPIDEV0 must be loaded via /boot/uEnv.txt to config pmux properly

    SBC="BBG/BBB"
    SLOTS7_FN="/sys/devices/bone_capemgr.*/slots"
    SLOTS8_FN="/sys/devices/platform/bone_capemgr/slots"

    if ls ${SLOTS7_FN} > /dev/null 2>&1 ; then
        DEBIAN=7
        # do not use USE_SPIDEV on Debian 7
        USE_SPIDEV=0
        LOAD_SPIDEV=yes
        LOAD_SPIPIO=yes
        SLOTS_FN=${SLOTS7_FN}
        UBOOT_OVERLAY=false
    elif test \( -f ${SLOTS8_FN} \) ; then
        DEBIAN=8
        USE_SPIDEV=1
        LOAD_SPIDEV=no
        LOAD_SPIPIO=no
        SLOTS_FN=${SLOTS8_FN}
        UBOOT_OVERLAY=false
    else
        DEBIAN=10
        USE_SPIDEV=1
        LOAD_SPIDEV=no
        LOAD_SPIPIO=no
        SLOTS_FN=
        UBOOT_OVERLAY=true
    fi

    DEVID=cape-bone-${DEV}

    if [ "x${USE_SPIDEV}" = "x1" ] ; then
        # use SPIDEV driver (with built-in DMA) for SPI:
        USE_SPI="USE_SPIDEV"
        DEV_SPI=SPIDEV0
        DEVID_SPI=BB-${DEV_SPI}
        LOAD_SPI=${LOAD_SPIDEV}
    else
        USE_SPI="USE_SPIPIO"
        DEV_SPI=${DEV}-S
        DEVID_SPI=cape-bone-${DEV_SPI}
        LOAD_SPI=${LOAD_SPIPIO}
    fi

    DEV_PRU=${DEV}-P
    DEVID_PRU=cape-bone-${DEV_PRU}

    CAPE=${DEVID}-00A0
    SPI=${DEVID_SPI}-00A0
    PRU=${DEVID_PRU}-00A0
fi

echo ${SBC} "DEBIAN-"${DEBIAN} ${USE_SPI}

# cape
if [ "x${BBAI}" = "xtrue" ] ; then
    echo "BBAI uses custom Kiwi device tree loaded via U-boot"
elif [ "x${RPI}" = "xtrue" ] ; then
    modprobe i2c-dev
    modprobe at24
    echo "24c32 0x54" > /sys/class/i2c-adapter/i2c-1/new_device
else
    if test \( ! -f /lib/firmware/${CAPE}.dtbo \) -o \( /lib/firmware/${CAPE}.dts -nt /lib/firmware/${CAPE}.dtbo \) ; then
        echo compile ${DEV} device tree;
        (cd /lib/firmware; dtc -O dtb -o ${CAPE}.dtbo -b 0 -@ ${CAPE}.dts);
        # don't unload old slot because this is known to cause panics; must reboot
    fi

    if [ "x${UBOOT_OVERLAY}" = "xtrue" ] ; then
        echo "Kiwi device tree loaded via U-boot overlay"
        
        # easier to do this way than via U-boot
        config-pin p9.17 spi_cs
        config-pin p9.18 spi
        config-pin p9.21 spi
        config-pin p9.22 spi_sclk
    else
        echo "Kiwi and SPI device tree loaded via capemgr"

        if ! grep -q ${DEVID} ${SLOTS_FN} ; then
            echo load ${DEV} device tree;
            echo ${DEVID} > ${SLOTS_FN};
        fi

        # SPI
        if test \( -f /lib/firmware/${SPI}.dts \) -a \( \( ! -f /lib/firmware/${SPI}.dtbo \) -o \( /lib/firmware/${SPI}.dts -nt /lib/firmware/${SPI}.dtbo \) \) ; then
            echo compile ${DEV_SPI} device tree;
            (cd /lib/firmware; dtc -O dtb -o ${SPI}.dtbo -b 0 -@ ${SPI}.dts);
            # don't unload old slot because this is known to cause panics; must reboot
        fi

        if [ "x${LOAD_SPI}" = "xyes" ] ; then
            if ! grep -q ${DEVID_SPI} ${SLOTS_FN} ; then
                echo load ${DEV_SPI} device tree;
                echo ${DEVID_SPI} > ${SLOTS_FN};
            fi
        fi

        # PRU (future)
        if test \( ! -f /lib/firmware/${PRU}.dtbo \) -o \( /lib/firmware/${PRU}.dts -nt /lib/firmware/${PRU}.dtbo \) ; then
            echo compile ${DEV_PRU} device tree;
            (cd /lib/firmware; dtc -O dtb -o ${PRU}.dtbo -b 0 -@ ${PRU}.dts);
            # don't unload old slot because this is known to cause panics; must reboot
        fi

        if ! grep -q ${DEVID_PRU} ${SLOTS_FN} ; then
            echo load ${DEV_PRU} device tree;
            echo ${DEVID_PRU} > ${SLOTS_FN};
        fi
    fi
fi

echo PROG = ${PROG} -debian ${DEBIAN} -use_spidev ${USE_SPIDEV} ${ARGS}
${PROG} -debian ${DEBIAN} -use_spidev ${USE_SPIDEV} ${ARGS}
