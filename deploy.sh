#!/bin/sh
#
# Deploy a Tezos node on GCP
#

# Tezos packaging and snapshotting
#
PKGSITE="https://pkgbeta.tzinit.org"
VERS=19.0rc1
REV=1
SNAPREG="eu"

# Tezos network defaults
#
NETWORK="mainnet"
MODE="rolling"
RPCALLOWLIST="null"
RPC="no"

# GCP Defaults
#
GCLOUDSITE="https://cloud.google.com/sdk/docs/install"
MACHINE="e2-standard-4"
OS=debian-12
ARCH=amd64

# Disc sizes (root currently unused because it is a pain to
# deal with a second disc)
#
DISC_ROOT="20"
DISC_ROLLING="100"
DISC_FULL="300"
DISC_ARCHIVE="2000"
DISC_SIZE="100" # Default disc size

# External helper script to use
#
HELPERSCRIPT="_helper.sh"

WARNTIME=10

warn() {
    echo "$1" >&2
}

leave() {
    echo "$1" >&2
    exit 1
}

usage() {
    leave "Usage: $0 -p project -z zone [...options...] [name]
    where options are:
        -p project - specify the GCP project to use (mandatory)
        -z zone    - specify the GCP zone to use (mandatory) 
        -t type    - the type of node required rolling (default) or full or archive
        -n network - the Tezos network (default is mainnet)
        -R address list - RPC allow list for firewall
        -s region  - snapshot server region: eu (default), asia or us
        -m machine - GCP profile (default is e2-standard-4)
        -d size    - Size of disc (defaults for each type)
        -o OS      - GCP name for OS (defaults to debian-12)
        -v ver     - version of Octez
        -r revision - package revision
        -F         - follow the installation log
        -S         - continue even if there are no snapshots
        -W         - suppress disclaimer

    and
        name       - the name of the node (or we construct one)" 
}
#         -c         - CLI options to give to the node
#        -C         - CLOUD (aws, google or azure)

# Setup
#
TMPLOG=`mktemp /tmp/_deployXXXXXX`

ZONECLI=""
PROJECTCLI=""
ZONE=""
PROJECT=""

FOLLOW="0"
IGNORESNAP="no"

# Initial checks
#
which gcloud >/dev/null 2>&1
[ "$?" != "0" ] && \
    leave "Please install gcloud from $GCLOUDSITE and log in to your GCP account"

which wget > /dev/null 2>&1
[ "$?" != "0" ] && \
    leave "Please install wget on your machine"


# Command-line magic
#
while [ $# -gt 0 ]; do
        case $1 in
        -d)     DISC_SIZE="$2"; shift ;;
#        -c)     CLI="$2"; echo "Warning -c not implemented yet"; shift ;;
#        -C)     CLOUD="$2"; echo "Warning -C CLOUD not implented yet"; shift ;;
        -m)     MACHINE="$2"; shift; ;;
        -n)     NETWORK="$2"; shift; ;;
        -o)     OS="$2"; shift; ;;
        -p)     PROJECT="$2"; shift; ;;
        -r)     REV="$2"; shift; ;;
        -R)     RPCALLOWLIST="$2"; shift; ;;
        -s)     SNAPREG="$2"; shift; ;;
        -S)     IGNORESNAP="yes"; ;;
        -t)     MODE="$2"; shift; ;;
        -v)     VERS="$2"; shift; ;;
        -z)     ZONE="$2" shift; ;;
        -F)     FOLLOW=1; ;;
        -W)     WARNTIME=0; ;;
        -*)     usage; ;;
        *)      break; # rest of args are targets
        esac
        shift
done

NAME="tezos-node-$NETWORK-$MODE"
[ ! -z "$1" ] && NAME="$1"

[ -z "$ZONE" ] && leave "Zone must be specified with -z"
[ -p "$PROJECT" ] && leave "Project must be specified with -p"

ZONECLI="--zone $ZONE"
PROJECTCLI="--project $PROJECT"

# Check valid region
#
case $SNAPREG in
    eu)
        ;;
    asia|us)
        [ "$MODE" = "archive" ] && warn "Archives on in region eu"
        ;;
    *)
        leave "Unknown region $SNAPREG";
esac
        
# Specific mode handling here
#
case $MODE in 
    rolling)
        DISC_SIZE=${DISC_ROLLING};
        ;;

    full)
        DISC_SIZE=${DISC_FULL};
        ;;

    archive)
        DISC_SIZE=${DISC_ARCHIVE};
        ;;

    *)
        leave "Unknown node mode $MODE"
esac

# Disclaimer
#
if [ "$WARNTIME" != "0" ]; then
    echo "WARNING: This script will bring up resources on GCP and they will cost money"
    echo "WARNING: Please make sure you understand your budget"
    echo "Ctrl-C now to exit if you are worried - you have $WARNTIME seconds"
    sleep $WARNTIME
fi

# Client package
#
CLIENTPKG="octez-client_${VERS}-${REV}_${ARCH}.deb" 

echo "===> Checking that packages exist"
wget -O /dev/null $PKGSITE/$OS/$CLIENTPKG > /dev/null 2>&1
[ "$?" != "0" ] && echo "Cannot find Octez package for ${OS} and version ${VERS}-${REV}" && exit 2

if [ "$IGNORESNAP" != "yes" ]; then
    echo "===> Checking that snapshot is available"
    TAIL=$MODE
    [ "$MODE" = "archive" ] && TALE=archive.tar.lz4
    gcloud storage ls gs://tf-snapshot-${REG}/${NETWORK}/${TAIL} >/dev/null 2>&1
    [ "$?" != "0" ] && leave "Cannot find a snapshot for $NETWORK/$MODE"
fi

echo "===> Enabling compute engine"
gcloud services enable compute.googleapis.com ${PROJECTCLI}

echo "===> Finding OS image for $OS"
IMAGE=$(gcloud compute images list | grep " $OS " | awk -F' ' '{print $1}')
[ "$?" != "0" ] && leave "Cannot find a GCP image for $OS"
echo ${IMAGE}

echo "===> Setting up Node $NAME ($NETWORK/$MODE)"

gcloud compute instances create ${NAME} \
    ${PROJECTCLI} ${ZONECLI} \
    --machine-type=${MACHINE} \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=${NAME},image=projects/debian-cloud/global/images/${IMAGE},mode=rw,size=${DISC_SIZE},\
type=projects/${PROJECT}/zones/${ZONE}/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any > $TMPLOG 2>&1
[ "$?" != "0" ] && cat "$TMPLOG" && leave "Cannot create VM instance"

echo "===> Waiting gracefully for node to come up"
sleep 30

if [ "$RPCALLOWLIST" != "null" ]; then
    echo "===> Adding firewall rule for RPC"
    gcloud compute ${PROJECTCLI} firewall-rules create ${NAME}-rpcallowlist \
        --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
        --rules=tcp:8732 --source-ranges="${RPCALLOWLIST}" > $TMPLOG 2>&1
        [ "$?" != "0" ] && cat "$TMPLOG" && echo "Cannot create filewall rule (may already exist)"
    RPC=yes
fi



echo "===> Login with:"
echo "gcloud compute ssh ${PROJECTCLI} ${ZONECLI} ${NAME}"
echo "===> Decommission with:"
echo "gcloud compute instances delete --quiet ${PROJECTCLI} ${ZONECLI} ${NAME}"
echo "gcloud compute firewall-rules delete --quiet ${NAME}-rpcallowlist ${PROJECTCLI}"

echo "===> Copying and executing setup script"
gcloud compute scp ${PROJECTCLI} ${ZONECLI} ${HELPERSCRIPT} \
            ${NAME}:/tmp/setup.sh

gcloud compute ssh ${PROJECTCLI} ${ZONECLI} \
    ${NAME} --command "nohup sudo sh /tmp/setup.sh ${NETWORK} ${MODE} ${RPC} ${SNAPREG} ${PKGSITE} ${OS} ${ARCH} ${VERS}-${REV} > /tmp/install.log 2>&1 &"

echo "===> Script running"
rm -f "$TMPLOG"

if [ "$FOLLOW" = "1" ]; then
    echo "===> Following log - it is safe to CTRL-C now if you want to exit"
    sleep 3
    gcloud compute ssh ${PROJECTCLI} ${ZONECLI} \
        ${NAME} --command "tail -f /tmp/install.log"
fi

