#!/bin/sh

set -e

cleanup() {
	exec 1>&3
	exec 2>&4
	if [ -r "$IPSET_TMP/setlist.res" ]; then
		cat "$IPSET_TMP/setlist.res"
		rm -f "$IPSET_TMP/setlist.res"
	fi
}
trap cleanup EXIT

exec 3>&1
exec 4>&2
exec > "$IPSET_TMP/setlist.res" 2>&1

set -x

ipset=${IPSET_BIN:-../src/ipset}

loop=8

fail() {
	echo "FAILED: $0 $@"
	exit 1
}

n=0
while [ $n -le 9 ]; do
    egrep '^(ip_set_|xt_set)' /proc/modules | while read x y; do
    	rmmod $x || :
    done
    if [ "`egrep '^(ip_set_|xt_set)' /proc/modules`" ]; then
    	sleep 1s
    else
    	echo "Modules unloaded after $n attempts."
    	n=10
    fi
done
rmmod ip_set >/dev/null 2>&1 || :

create() {
    n=$1
    while [ $n -le 1024 ]; do
      echo "c test$n hash:ip"
    	n=$((n+2))
    done | $ipset restore
}

for x in `seq 1 $loop`; do
    # echo "test round $x"
    create 1 &
    create 2 &
    wait
    test `$ipset l -n | wc -l` -eq 1024 || fail "expected 1024 sets"
    $ipset x
    # Wait for destroy to be finished and reference counts releases
    n=0
    ref=0
    while [ $n -le 9 ]; do
    	ref=`lsmod|grep -w ^ip_set_hash_ip | awk '{print $3}'`
    	if [ $ref -eq 0 ]; then
    	    n=10;
    	else
    	    sleep 1s
    	    n=$((n+1))
    	fi
    done
    if [ "$ref" -ne 0 ]; then
    	lsmod
    	echo $ref
    fi
    test "$ref" -eq 0 || fail "ref was $ref"
    rmmod ip_set_hash_ip >/dev/null 2>&1
    rmmod ip_set >/dev/null 2>&1
done

rm -f "$IPSET_TMP/setlist.res"
cleanup
