# AWS factorisation
#
AWSDOCSITE="XXX"
MACHINE="t3.micro" # XXX
PNZMANDATORY=yes

software_checks() {
    which aws >/dev/null 2>&1
    [ "$?" != "0" ] && echo "Please install aws command line tools" \
    	&& echo "cf $AWSDOCSITE" && echo "and setup your credentials" \
	&& exit 1
}

enable_compute() {
    # Usage: enable_compute PROJECT
    #
    true
}

findosimage() {
    # Usage: findosimage OS
    P=$1
    IMAGE="ilikesarm"
#    IMAGE=$(gcloud compute images list | grep " $P " | awk -F' ' '{print $1}')
    [ "$?" != "0" ] && leave "Cannot find a OS image for $P"
    echo $IMAGE
}

create_vm() {

    TMPLOG=`mktemp /tmp/_deployXXXXXX`
    echo "aws ec2 run-instances --image-id $5 --instance-type $4 \
		--region=$3 \
    		--profile=$2 --key-name=XXX --dry-run
        > $TMPLOG 2>&1
    "
# [
#    {
#        "DeviceName": "/dev/sda",
#        "Ebs": {
#            "VolumeSize": $6
#        }
#    }
#]
    [ "$?" != "0" ] && cat "$TMPLOG" && leave "Cannot create VM instance"
    rm -f ${TMPLOG}
}

wait_gracefully() {
	echo "===> Waiting gracefully for node to come up"
	sleep 30
}


create_firewall() {
	echo "===> Adding firewall rule for RPC"
    TMPLOG=`mktemp /tmp/_deployXXXXXX`
#    gcloud compute firewall-rules create $1-rpcallowlist  --project=$2 \
#        --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
#        --rules=tcp:8732 --source-ranges="$3" > $TMPLOG 2>&1
#        [ "$?" != "0" ] && cat "$TMPLOG" && echo "Cannot create filewall rule (may already exist)"
    rm -f ${TMPLOG}
}

print_ssh_details() {
    P=$1
    Z=$2
    N=$3
    DE="no"
    [ ! -z "$4" ] && DE=$4

    if [ "$DE" = "no" ]; then
        echo "===> Login with:"
#        echo "gcloud compute ssh --project=${P} --zone=${Z} ${N}"
        echo "===> Decommission with:"
    fi
#    echo "gcloud compute instances delete --quiet --project=${P} --zone=${Z} ${N}"
#    echo "gcloud compute firewall-rules delete --quiet ${N}-rpcallowlist --project=${P}"
}

copy_and_exec() {
    P=$1
    Z=$2
    H=$3
    N=$4
    CLI=$5

	echo "===> Copying and executing setup script"	
#    gcloud compute scp --project=$P --zone=$Z $H \
#            ${N}:/tmp/setup.sh

#    gcloud compute ssh --project=$P --zone=$Z \
#        $N --command "nohup sudo sh /tmp/setup.sh $CLI > /tmp/install.log 2>&1 &"

}

getip() {
#    gcloud compute instances describe --project=$1 --zone=$2 $3 | grep natIP | sed -e 's/.*natIP: //g'
	true
}

followlog() {
#    gcloud compute ssh --project=$1 --zone=$2 \
#        $3 --command "tail -f /tmp/install.log"
	true

}
