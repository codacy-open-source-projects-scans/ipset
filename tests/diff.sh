#!/bin/bash

NEW_DUMP="$IPSET_TMP/kernel-dump.sed"
STORED_DUMP="$IPSET_TMP/$2.sed"

sed -e 's/timeout [0-9]*/timeout x/' -e 's/initval 0x[0-9a-fA-F]\{8\}/initval 0x00000000/' "$1" > "$NEW_DUMP"
sed -e 's/timeout [0-9]*/timeout x/' -e 's/initval 0x[0-9a-fA-F]\{8\}/initval 0x00000000/' "$2" > "$STORED_DUMP"

diff -u -I 'Revision: .*' -I 'Size in memory.*' "$STORED_DUMP" "$NEW_DUMP"
ret=$?

rm -f "$STORED_DUMP" "$NEW_DUMP"

exit $ret
