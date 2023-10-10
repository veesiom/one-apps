#!/bin/bash
echo "running packer"

DISTRO=$1
DST=$2
DIR_CURR=$(dirname $0)
DIR_OUT=$DIR_INSTALL
BASE_IMAGE=$DIR_BASE/$DISTRO.img

packer build -force \
    -var "alpine_base_image=${BASE_IMAGE}" \
    -var "qemu_binary=${QEMU_BINARY}" \
    -var "appliance_name=${DISTRO}" \
    -var "distro=${DISTRO}" \
    -var "http_dir=${DIR_CURR}" \
    -var "output_dir=${DIR_PACKER}" \
    $DIR_CURR/alpine.json

mv $DIR_PACKER/$DISTRO $DST
