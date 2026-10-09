#!/bin/bash

# set -x

ipset=${IPSET_BIN:-../src/ipset}
tmpdir=""

tests="init"
tests="$tests ipmap bitmap:ip"
tests="$tests macipmap portmap"
tests="$tests iphash hash:ip hash:ip6"
tests="$tests ipporthash hash:ip,port hash:ip6,port"
tests="$tests ipmarkhash hash:ip,mark hash:ip6,mark"
tests="$tests ipportiphash hash:ip,port,ip hash:ip6,port,ip6"
tests="$tests nethash hash:net hash:net6 hash:net,port hash:net6,port"
tests="$tests hash:ip,port,net hash:ip6,port,net6 hash:net,net hash:net6,net6"
tests="$tests hash:net,port,net hash:net6,port,net6"
tests="$tests hash:net,iface.t hash:mac.t"
tests="$tests comment setlist restore"
# tests="$tests iptree iptreemap"

if [ "$IPSET_UNSHARED" = "" ]; then
	# Re-execute in new network namespace
	export IPSET_UNSHARED="yes"
	export IPSET_BIN="$ipset"
	sysctl net.netfilter.nf_log_all_netns=1
	exec unshare -n -- "$0" "$@"
fi

sysctl net.ipv4.conf.all.rp_filter=0

cleanup() {
	rm -f "$tmpdir"/.foo*
	rm -f "$tmpdir/.loglines"
	rmdir "$tmpdir"
	ip link del eth0
}
trap cleanup EXIT

kmemleak_found=0
test -f /sys/kernel/debug/kmemleak && kmemleak_found=$(grep "unreferenced object" /sys/kernel/debug/kmemleak | wc -l)

check_kmemleak_force()
{
	echo scan > /sys/kernel/debug/kmemleak

	local lines=$(grep "unreferenced object" /sys/kernel/debug/kmemleak | wc -l)
	if [ $lines -ne $kmemleak_found ];then
		echo "FAILED"
		cat /sys/kernel/debug/kmemleak
		failcount=$((failcount+1))
	else
		echo "OK"
	fi
}

check_failcount() {
	local ret=0

	if [ -f /sys/kernel/debug/kmemleak ]; then
		echo -n  "Waiting 30 seconds, then doing kmemleak scan "
		sleep 30
		check_kmemleak_force
	fi

	rmmod ip_set >/dev/null 2>&1

	if [ "$failcount" -eq 0 ]; then
		echo "All tests are passed"
	else
		echo "$failcount tests have failed"
		ret=1
	fi

	exit $ret
}

tmpdir=$(mktemp -t -d ip-set-XXXXXXXX)

ip link set lo up

# test cases send and expect packets on eth0.
ip link add dev eth0 type dummy
ip link set eth0 up
ip addr add 10.255.255.64/8 dev eth0
sysctl net.ipv4.conf.eth0.rp_filter=0

# For correct sorting:
LC_ALL=C
export LC_ALL
export IPSET_TMP="$tmpdir"

HAVE_SENDIP=n
[ -n "`which sendip`" ] && HAVE_SENDIP=y
if [ $HAVE_SENDIP = "n" ]; then
	if python -c 'from scapy.all import ( IPv6 )'; then
		HAVE_SENDIP=y
	fi
fi

add_tests() {
	# inet|inet6 network
	if [ $1 = "inet" ]; then
		cmd=iptables-save
		add="match_target match_flags"
	else
		cmd=ip6tables-save
		add=match_target6
	fi
	#line="`dmesg | tail -1 | cut -d " " -f 2-`"
	#if [ ! -e /var/log/kern.log -o -z "`grep -F \"$line\" /var/log/kern.log`" ]; then
	#	echo "The destination for kernel log is not /var/log/kern.log, skipping $1 match and target tests"
	#	return
	#fi
	c=${cmd%%-save}
	if [ "`$c -m set -h 2>&1| grep 'cannot open shared object'`" ]; then
		echo "$c does not support set match, skipping $1 match and target tests"
		return
	fi
	if [ `$cmd -t filter | wc -l` -eq 7 -a \
	     `$cmd -t filter | grep ACCEPT | wc -l` -eq 3 ]; then
		if [ "$HAVE_SENDIP" = "n" ]; then
	     		echo "sendip utility is missig: skipping $1 match and target tests"
	     		return
	     	elif [ -n "`which ss`" ]; then
	     		if [ -n "`ss -f $1 -t -u -a | grep $2`" ]; then
	     			echo "Our test network $2 in use: skipping $1 match and target tests"
	     			return
	     		fi
	     	elif [ -n "`which netstat`" ]; then
	     		if [ -n "`netstat --protocol $1 -n | grep $2`" ]; then
	     			echo "Our test network $2 in use: skipping $1 match and target tests"
	     			return
	     		fi
	     	else
	     		echo "Cannot check test network, skipping $1 match and target tests"
	     		return
	     	fi
	     	tests="$tests $add"
	else
		echo "You have got iptables rules: skipping $1 match and target tests"
	fi
}

if [ "$1" ]; then
	tests="init $@"
else
	add_tests inet 10.255.255
	add_tests inet6 1002:1002:1002:1002::
fi

# Make sure the scripts are executable
for f in check_* *.sh; do
	test -x "$f" || chmod a+x "$f"
done

failcount=0
for types in $tests; do
    $ipset -X test >/dev/null 2>&1
    if [ -f $types ]; then
    	filename=$types
    else
    	filename=$types.t
    fi
    while read ret cmd; do
	case $ret in
	    \#)
	    	if [ "$cmd" = "eof" ]; then
	    		break
	    	fi
	    	what=$cmd
		continue
		;;
	    skip)
		eval $cmd >/dev/null
	    	if [ $? -ne 0 ]; then
	    		echo "Skipping tests, '$cmd' failed"
	    		break
	    	fi
	    	continue
	    	;;
	    require_sendip)
		if [ "$HAVE_SENDIP" = "y" ]; then
			continue
		else
			echo "Skipping, sendip (scapy) not available"
			break
		fi
		;;
	    *)
		;;
	esac
	echo -ne "$types: $what: "
	cmd=`echo $cmd | sed "s|ipset|$ipset 2>"$tmpdir"/.foo.err|"`
	# For the case: ipset list | ... | xargs -n1 ipset
	cmd=`echo $cmd | sed "s|ipset|$ipset|2g"`
	eval $cmd
	r=$?
	# echo $ret $r
	if [ "$ret" = "$r" ]; then
		echo "passed"
	else
		echo "FAILED"
		echo "Failed test: $cmd"
		cat "$tmpdir"/.foo.err
		let "failcount++"
		break
	fi
	# sleep 1
    done < $filename
done
# Remove test sets created by setlist.t
$ipset -X >/dev/null 2>&1
for x in $tests; do
	case $x in
	init)
		;;
	*)
		for x in `lsmod | grep ip_set_ | awk '{print $1}'`; do
			rmmod $x >/dev/null 2>&1
		done
		;;
	esac
done

check_failcount
