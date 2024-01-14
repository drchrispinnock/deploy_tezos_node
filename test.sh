#!/bin/sh

# Test suite(TM)
#
# This is expensive
#
PROJECT=chris-temp-test-deploy-script
ZONE=europe-west6-a
NETWORKS="nairobinet oxfordnet ghostnet mainnet"
MODES="rolling full archive"
cleanupscript="test_cleanup.$$.sh"

HOSTLIST=""

export TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=yes

[ ! -z "$1" ] && NETWORKS="$1"
[ ! -z "$2" ] && MODES="$2"

# Avoid publishing IP addresses in Git
#
RPC=""
if [ -f "rpcip" ]; then
	RPC="-R `cat rpcip`"
fi

rm -f $cleanupscript
for net in ${NETWORKS}; do
	for mode in ${MODES}; do

		echo "===> Deploying ${net}/${mode}"
		host=test-$mode-$net
		sh deploy.sh -W -z $ZONE -p $PROJECT -s eu -n ${net} -t $mode ${RPC} $host > log.$net.$mode.txt 2>&1
		if [ "$?" != "0" ]; then
			echo "FAILED: see log.$net.$mode.txt"
		else
			HOSTLIST="$HOSTLIST $host"
		fi

		echo "gcloud compute instances delete --quiet --project=${PROJECT} --zone=${ZONE} $host" >> $cleanupscript
		echo "gcloud compute firewall-rules delete --quiet $host-rpcallowlist --project=${PROJECT}" >> $cleanupscript
		echo "rm -f log.$net.$mode.txt" >> $cleanupscript

	done
done
echo "rm -f $cleanupscript" >> $cleanupscript

[ -z "$RPC" ] && echo "No RPC setup - exiting" && exit 0

# Get IPs and check bootstrapped
#
while [ ! -z "$HOSTLIST" ]; do
	NHOSTLIST=""
	
	echo "===> Sleeping..."
	sleep 300 # 5 minutes

	for host in $HOSTLIST; do
		_IP=`gcloud compute instances describe --project=${PROJECT} --zone=${ZONE} ${host} | grep natIP | sed -e 's/.*natIP: //g'`
		printf "===> Testing host $host ($_IP): "
		octez-client -E http://$_IP:8732 bootstrapped >/dev/null 2>&1
		if [ "$?" != "0" ]; then
			 echo "Cannot connect"
			 NHOSTLIST="$NHOSTLIST $host"
		else
			echo "Bootstrapped"
			octez-client -E http://$_IP:8732 bootstrapped
			echo "===> Decommissioning $host"
			gcloud compute instances delete --quiet --project=${PROJECT} --zone=${ZONE} $host >/dev/null 2>&1
			gcloud compute firewall-rules delete --quiet $host-rpcallowlist --project=${PROJECT} >/dev/null 2>&1
		fi

	done
	HOSTLIST="$NHOSTLIST"

done

echo "===> Running cleanup script"
sh $cleanupscript


