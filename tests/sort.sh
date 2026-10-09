#!/bin/sh

sed '/Members:/q' "$1" > "$IPSET_TMP/.foo"
awk '/Members:/,EOF' "$1" | grep -v 'Members:' | sort >> "$IPSET_TMP/.foo"
rm -f "$1"
