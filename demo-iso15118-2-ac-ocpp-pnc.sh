#!/usr/bin/env bash


DEMO_REPO="https://github.com/sahabul/everest-demo.git"
DEMO_BRANCH="ocpp-pnc-demo-mre"

MAEVE_REPO="https://github.com/thoughtworks/maeve-csms.git"
MAEVE_BRANCH="b990d0eddf2bf80be8d9524a7b08029fbb305c7d" # patch files are based on this commit


usage="usage: $(basename "$0") [-r <repo>] [-b <branch>] [-j|1|2|3] [-h]

This script will run EVerest ISO 15118-2 AC charging with OCPP demos.

Pro Tip: to use a local copy of this everest-demo repo, provide the current
directory to the -r option (e.g., '-r \$(pwd)').

where:
    -r   URL to everest-demo repo to use (default: $DEMO_REPO)
    -b   Branch of everest-demo repo to use (default: $DEMO_BRANCH)
    -j   OCPP v1.6j
    -1   OCPP v2.0.1 Security Profile 1
    -2   OCPP v2.0.1 Security Profile 2
    -3   OCPP v2.0.1 Security Profile 3
    -h   Show this message"


DEMO_VERSION=
DEMO_COMPOSE_FILE_NAME=


# loop through positional options/arguments
while getopts ':r:b:j123h' option; do
  case "$option" in
    r)  DEMO_REPO="$OPTARG" ;;
    b)  DEMO_BRANCH="$OPTARG" ;;
    j)  DEMO_VERSION="v1.6j"
        DEMO_COMPOSE_FILE_NAME="docker-compose.ocpp16j.yml" ;;
    1)  DEMO_VERSION="v2.0.1-sp1"
        DEMO_COMPOSE_FILE_NAME="docker-compose.ocpp201.yml" ;;
    2)  DEMO_VERSION="v2.0.1-sp2"
        DEMO_COMPOSE_FILE_NAME="docker-compose.ocpp201.yml" ;;
    3)  DEMO_VERSION="v2.0.1-sp3"
        DEMO_COMPOSE_FILE_NAME="docker-compose.ocpp201.yml" ;;
    h)  echo -e "$usage"; exit ;;
    \?) echo -e "illegal option: -$OPTARG\n" >&2
        echo -e "$usage" >&2
        exit 1 ;;
  esac
done


if [[ ! "${DEMO_VERSION}" ]]; then
  echo 'Error: no demo version option provided.'
  echo
  echo -e "$usage"

  exit 1
fi


DEMO_DIR="$(mktemp -d)"


if [[ ! "${DEMO_DIR}" || ! -d "${DEMO_DIR}" ]]; then
  echo 'Error: Failed to create a temporary directory for the demo.'
  exit 1
fi


delete_temporary_directory() { rm -rf "${DEMO_DIR}"; }
trap delete_temporary_directory EXIT


echo "DEMO REPO:    $DEMO_REPO"
echo "DEMO BRANCH:  $DEMO_BRANCH"
echo "DEMO VERSION: $DEMO_VERSION"
echo "DEMO CONFIG:  $DEMO_COMPOSE_FILE_NAME"
echo "DEMO DIR:     $DEMO_DIR"


cd "${DEMO_DIR}" || exit 1


echo "Cloning EVerest from ${DEMO_REPO} into ${DEMO_DIR}/everest-demo"
git clone --branch "${DEMO_BRANCH}" "${DEMO_REPO}" everest-demo


pushd everest-demo || exit 1
docker compose --project-name everest-ac-demo --file "${DEMO_COMPOSE_FILE_NAME}" up -d --wait

if [[ "$DEMO_VERSION" =~ sp2 || "$DEMO_VERSION" =~ sp3 ]]; then
  docker cp manager/cached_certs_correct_name.tar.gz everest-ac-demo-manager-1:/workspace/
  docker exec everest-ac-demo-manager-1 /bin/bash -c "tar xf cached_certs_correct_name.tar.gz"

  echo "Configured everest certs, validating that the chain is set up correctly"
  docker exec everest-ac-demo-manager-1 /bin/bash -c "openssl verify -show_chain -CAfile dist/etc/everest/certs/ca/v2g/V2G_ROOT_CA.pem --untrusted dist/etc/everest/certs/ca/csms/CPO_SUB_CA1.pem --untrusted dist/etc/everest/certs/ca/csms/CPO_SUB_CA2.pem dist/etc/everest/certs/client/csms/CSMS_LEAF.pem"
fi

docker cp /home/sahabul/Sandia/Everest/everest-demo/manager/device_model_storage_maeve_sp1.db everest-ac-demo-manager-1:/workspace/dist/share/everest/modules/OCPP201/device_model_storage.db
docker cp /home/sahabul/Sandia/Everest/everest-workspace-latest/everest-core/config/config-sil-ocpp201-pnc.yaml  everest-ac-demo-manager-1:/ext/source/config/config-sil-ocpp201-pnc.yaml

if [[ "$DEMO_VERSION" =~ v2.0.1 ]]; then
  script=run-sil-ocpp201-pnc.sh
  echo "Starting software in the loop simulation using script ${script}"
  docker exec everest-ac-demo-manager-1 sh /workspace/build/run-scripts/$script
fi