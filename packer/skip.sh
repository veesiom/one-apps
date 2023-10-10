#!/bin/bash
echo "[INFO] Empty installer stage, creating symlink $DIR_INSTALL/$1.qcow2 -> $DIR_BASE/$1"
( cd $DIR_INSTALL; ln -f -s ../../$DIR_BASE/$1.img $1.qcow2 )
