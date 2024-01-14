# GCP factorisation
#
GCP_CLOUDSITE="https://cloud.google.com/sdk/docs/install"
MACHINE="e2-standard-4"

software_checks() {
    # None
    which gcloud >/dev/null 2>&1
    [ "$?" != "0" ] && echo "Please install gcloud from $GCP_CLOUDSITE and log in to your GCP account" && exit 1
}

enable_compute() {
    # Usage: enable_compute PROJECT
    #
    gcloud services enable compute.googleapis.com --project=$1
}

findosimage() {
    # Usage: findosimage OS
    P=$1
    IMAGE=$(gcloud compute images list | grep " $P " | awk -F' ' '{print $1}')
    [ "$?" != "0" ] && leave "Cannot find a OS image for $P"
    echo $IMAGE
}

create_vm() {

    TMPLOG=`mktemp /tmp/_deployXXXXXX`
    gcloud compute instances create $1 \
        --project=$2 --zone=$3 \
        --machine-type=$4 \
        --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --create-disk=auto-delete=yes,boot=yes,device-name=$1,image=projects/debian-cloud/global/images/$5,mode=rw,size=$6,\
type=projects/$2/zones/$3/diskTypes/pd-balanced \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=goog-ec-src=vm_add-gcloud \
        --reservation-affinity=any > $TMPLOG 2>&1
    [ "$?" != "0" ] && cat "$TMPLOG" && leave "Cannot create VM instance"
    rm -f ${TMPLOG}
}

create_firewall() {
    TMPLOG=`mktemp /tmp/_deployXXXXXX`
    gcloud compute firewall-rules create $1-rpcallowlist  --project=$2 \
        --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
        --rules=tcp:8732 --source-ranges="$3" > $TMPLOG 2>&1
        [ "$?" != "0" ] && cat "$TMPLOG" && echo "Cannot create filewall rule (may already exist)"
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
        echo "gcloud compute ssh --project=${P} --zone=${Z} ${N}"
        echo "===> Decommission with:"
    fi
    echo "gcloud compute instances delete --quiet --project=${P} --zone=${Z} ${N}"
    echo "gcloud compute firewall-rules delete --quiet ${N}-rpcallowlist --project=${P}"
}

copy_and_exec() {
    P=$1
    Z=$2
    H=$3
    N=$4
    CLI=$5

    gcloud compute scp --project=$P --zone=$Z $H \
            ${N}:/tmp/setup.sh

    gcloud compute ssh --project=$P --zone=$Z \
        $N --command "nohup sudo sh /tmp/setup.sh $CLI > /tmp/install.log 2>&1 &"

}

getip() {
    gcloud compute instances describe --project=$1 --zone=$2 $3 | grep natIP | sed -e 's/.*natIP: //g'
}

followlog() {
    gcloud compute ssh --project=$1 --zone=$2 \
        $3 --command "tail -f /tmp/install.log"

}