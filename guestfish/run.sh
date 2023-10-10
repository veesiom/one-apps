#!/bin/bash

DISTRO=$1
DST_IMG=$2
SRC_IMG=${DIR_INSTALL}/$DISTRO.qcow2
DIR_CURR=$(dirname "$0")

if [ -d "${DIR_CURR}/$DISTRO/scripts" ]; then
    # distro specific scripts
    SCRIPTS="$(echo ${DIR_CURR}/$DISTRO/scripts/*.sh)"
else
    # scripts_defaults
    SCRIPTS="$(echo ${DIR_CURR}/scripts_defaults/*.sh)"
fi

RUN_SCRIPTS_CMD=""
for S in $SCRIPTS; do
    RUN_SCRIPTS_CMD+="      : command /guestfish/$(basename $S)  "
done

GUESTFISH_CMD="guestfish --add ${SRC_IMG} \
    --inspector --network echo $DST_IMG \
    : rm-rf /context/ \
    : mkdir-p /context/ \
    : copy-in ./context-linux/out/. /context/ \
    : rm-rf /guestfish/ \
    : mkdir-p /guestfish/ \
    : copy-in $SCRIPTS /guestfish/ \
    : glob chmod 0755 /guestfish/* \
$RUN_SCRIPTS_CMD \
    : rm-rf /guestfish/"

eval "$GUESTFISH_CMD"

qemu-img convert -c -O qcow2 ${SRC_IMG} ${DST_IMG}
