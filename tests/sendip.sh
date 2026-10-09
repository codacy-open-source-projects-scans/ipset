#!/bin/bash

# Save lineno for checking
wc -l /var/log/kern.log 2>/dev/null | cut -d ' ' -f 1 > "$IPSET_TMP/.loglines"

if [ -n "`which sendip 2>/dev/null`" ]; then
	exec sendip "$@"
fi

exec ./sendip.py "$@"
