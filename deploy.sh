#!/bin/sh
#
# Deploy a Tezos node on GCP
#

warn() {
    echo "$1" >&2
}

leave() {
    echo "$1" >&2
    exit 1
}

usage() {
    leave "Usage: $0 -p project -z zone [...options...] name
    where options are:
        -p project - specify the GCP project to use (mandatory)
        -z zone    - specify the GCP zone to use (mandatory) 
        -t type    - the type of node required rolling (default) or full or archive
        -n network - the Tezos network (default is mainnet)
        -s region  - snapshot server region: eu (default), asia or us
        -m machine - GCP profile (default is e2-standard-4)
        -d size    - Size of disc (defaults for each type)
        -o OS      - GCP name for OS (defaults to debian-12)
        -v ver     - version of Octez
        -F         - follow the installation log
    and
        name       - the name of the node" 
}

# Defaults
#
GCLOUDSITE="https://XXX"
PKGSITE="https://pkgbeta.tzinit.org"

TMPLOG=`mktemp /tmp/_deployXXXXXX`

HELPERSCRIPT="_helper.sh"

MACHINE="e2-standard-4"

DISC_ROOT="20"
DISC_ROLLING="100"
DISC_FULL="300"
DISC_ARCHIVE="2000"
SIZE=""
_SIZE="100"

OS=debian-12

MODE="rolling"
SNAPREG="eu"
NETWORK="mainnet"

ZONECLI=""
PROJECTCLI=""
ZONE=""
PROJECT=""

FOLLOW="0"

# Initial checks
#
which gcloud >/dev/null 2>&1
[ "$?" != "0" ] && \
    leave "Please install gcloud from $GCLOUDSITE and log in to your GCP account"

# Command-line magic
#
while [ $# -gt 0 ]; do
        case $1 in
        -d)     SIZE="$2"; shift ;;
        -m)     MACHINE="$2"; shift; ;;
        -n)     NETWORK="$2"; shift; ;;
        -o)     OS="$2"; shift; ;;
        -p)     PROJECT="$2"; shift; ;;
        -s)     SNAPREG="$2"; shift; ;;
        -t)     MODE="$2"; shift; ;;
        -v)     VERS="$2"; shift; ;;
        -z)     ZONE="$2" shift; ;;
        -F)     FOLLOW=1; ;;
        -*)     usage; ;;
        *)      break; # rest of args are targets
        esac
        shift
done
[ -z "$1" ] && usage
NAME="$1"

[ -z "$ZONE" ] && leave "Zone must be specified with -z"
[ -p "$PROJECT" ] && leave "Project must be specified with -p"

ZONECLI="--zone $ZONE"
PROJECTCLI="--project $PROJECT"

# Check valid region
#
case $SNAPREG in
    eu|asia|us)
        ;;
    *)
        leave "Unknown region $SNAPREG";
esac
        
# Specific mode handling here
#
case $MODE in 
    rolling)
        _SIZE=${DISC_ROLLING};
        ;;

    full)
        _SIZE=${DISC_FULL};
        ;;

    archive)
        _SIZE=${DISC_ARCHIVE};
        ;;

    *)
        leave "Unknown node mode $MODE"
esac

# OS Specific stuff here
#
case $OS in
    debian-11|debian-12)
        ;;
    ubuntu-20|ubuntu-22)
        ;;
    debian-12-arm64)
        ;;
    *)
        warn "$OS not supported at $PKGSITE"
        ;;
esac

[ -z "$SIZE" ] && SIZE=$_SIZE

# OS handling
#
echo "===> Finding OS image for $OS"
IMAGE=$(gcloud compute images list | grep " $OS " | awk -F' ' '{print $1}')
[ "$?" != "0" ] && leave "Cannot find a GCP image for $OS"
echo ${IMAGE}

echo "===> Setting up Google Cloud Node $NAME ($NETWORK/$MODE)"

gcloud compute instances create ${NAME} \
    ${PROJECTCLI} ${ZONECLI} \
    --machine-type=${MACHINE} \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=${NAME},image=projects/debian-cloud/global/images/${IMAGE},mode=rw,size=${SIZE},\
type=projects/${PROJECT}/zones/${ZONE}/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any > $TMPLOG 2>&1
[ "$?" != "0" ] && cat "$TMPLOG" && leave "Cannot create VM instance"

echo "===> Waiting gracefully for node to come up"
sleep 30

echo "===> Copying and executing setup script"
gcloud compute scp ${PROJECTCLI} ${ZONECLI} ${HELPERSCRIPT} \
            ${NAME}:/tmp/setup.sh

gcloud compute ssh ${PROJECTCLI} ${ZONECLI} \
    ${NAME} --command "nohup sudo sh /tmp/setup.sh ${NETWORK} ${MODE} ${SNAPREG} ${PKGSITE} ${OS} > /tmp/install.log 2>&1 &"

echo "===> Script running"
rm -f "$TMPLOG"

echo "===> Login with:"
echo "gcloud compute ssh ${PROJECTCLI} ${ZONECLI} ${NAME}"

if [ "$FOLLOW" = "1" ]; then
    echo "===> Following log - it is safe to CTRL-C now if you want to exit"
    sleep 3
    gcloud compute ssh ${PROJECTCLI} ${ZONECLI} \
        ${NAME} --command "tail -f /tmp/install.log"
fi

