#!/bin/bash
set -e
pushd $(dirname $0)
md5_cmd=md5

PARSEC_VERSION="1.0.0rc3"
PARSEC_TIMEOUT=60

if ! test -x /sbin/md5; then
  md5_cmd=md5sum
fi

if [ -z "$GG_THING_NAME" ]; then
  GG_THING_NAME=$(id -un)-GG-parsec
  if test -e /etc/hostname; then
    GG_THING_NAME=$(cat /etc/hostname)-GG-parsec
  fi

fi
# GreenGrass thing name must not contain dots
GG_THING_NAME=${GG_THING_NAME//\./_}

function update_git() {
  git submodule update --init --recursive
}

function build_greengrass_patched() {
  # Build GreenGrass docker image using key-op-prototype branch of AWS SDKs
  pushd ./parsec-greengrass-run-config/docker/
  docker build . \
        --tag parallaxsecond/greengrass_patched:latest \
        --progress plain
  popd
}

function build_greengrass_with_provider() {
  # Build the demo docker image including Parsec GG provider

  docker build . -f greengrass_demo/Dockerfile --tag parallaxsecond/greengrass_demo:latest  --progress plain
}

function build_parsec_image() {
  # Build Parsec+Mbed-Crypto provider docker image
  pushd ./parsec-testcontainers/
  ./build.sh
  popd
}

function build_parsec_tpm_image() {
  # Build Parsec+TPM provider docker image
  pushd ./parsec-testcontainers/
  ./build.sh parsec_tpm
  popd
}

function wait_for_parsec() {

  if [ "$1" == docker ] ; then
    echo "Waiting for Parsec service in parsec_docker_run container"
    PARSEC_TOOL_CMD="docker exec -it parsec_docker_run parsec-tool ping"
  else
    echo "Checking for Parsec service running on the host"
    PARSEC_TOOL_CMD="parsec-tool ping"
  fi

  WAIT_TIME=0
  while [ $WAIT_TIME -lt $PARSEC_TIMEOUT ]; do
    if $PARSEC_TOOL_CMD >/dev/null; then
      echo "Pasrec is ready"
      return
    fi
    WAIT_TIME=$((WAIT_TIME+2))
    sleep 2
  done

  if [ "$1" == docker ] ; then
    echo "ERROR: Parsec service in parsec_docker_run container is not functional"
  else
    echo "ERROR: Parsec service on the host is not functional"
  fi
  exit 1
}

function parsec_run() {
  # Run a container from Parsec+Mbed-Crypto or TPM provider image if exists
  # otherwise check if Parsec is running on the host

  if [ "$1" == "tpm" ]; then
    DOCKER_DEVICES="--device /dev/tpm0 --device /dev/tpmrm0"
    GG_PARSEC_STORE="GG_PARSEC_STORE_TPM"
    GG_PARSEC_SOCK="GG_PARSEC_SOCK_TPM"
  else
    DOCKER_DEVICES=""
    GG_PARSEC_STORE="GG_PARSEC_STORE"
    GG_PARSEC_SOCK="GG_PARSEC_SOCK"
  fi

  if docker image inspect parallaxsecond/parsec:${PARSEC_VERSION}${1} >/dev/null 2>&1; then
    docker rm -f parsec_docker_run 2> /dev/null
    docker run -d --name parsec_docker_run \
          -ti \
          -v ${GG_PARSEC_STORE}:/var/lib/parsec/mappings \
          -v ${GG_PARSEC_SOCK}:/run/parsec \
          $DOCKER_DEVICES \
           parallaxsecond/parsec:${PARSEC_VERSION}${1}
    wait_for_parsec docker
  else
    echo "INFO: Parsec image parallaxsecond/parsec:${PARSEC_VERSION}${1} is missing."
    echo "      Build it if Parsec running in a container is required"
    wait_for_parsec
  fi

}

function gg_run() {
  docker rm -f "${1}" 2> /dev/null

  for warn_env in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_SESSION_TOKEN; do
    if [ "${!warn_env}" == "" ]; then
      # AWS SDKs have a series of strategies for picking up config, env variables is just one
      # of them.
      echo "the env variable ${warn_env} is not set, container might fail later"
    fi
  done

  GG_ADDITIONAL_CMD_ARGS="--trusted-plugin /provider.jar"

  if inspect=$(docker container inspect parsec_docker_run 2>/dev/null | grep ":/run/parsec"); then
    # Parsec is running in a container
    PARSEC_SOCK_VOLUME=${inspect//\"/}
  else
    # Parsec is running on the host
    PARSEC_SOCK_VOLUME="/run/parsec:/run/parsec"
  fi

  # shellcheck disable=SC2086
  docker run ${3} \
         --name "${1}" \
         -e JAVA_OPTS="${JAVA_OPTS}" \
         -e GG_THING_NAME="${GG_THING_NAME}" \
         -e GG_THING_GROUP="${GG_THING_GROUP}" \
         -e GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS}" \
         -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
         -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
         -e AWS_REGION="${AWS_REGION}" \
         -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" \
         -e AWS_ROLE_PREFIX="${AWS_ROLE_PREFIX}" \
         -e AWS_BOUNDARY_POLICY="${AWS_BOUNDARY_POLICY}" \
         -v ${PARSEC_SOCK_VOLUME} \
         -v GG_HOME:/home/ggc_user \
         parallaxsecond/greengrass_demo:latest "${2}"
}

function provision_thing() {
  # Automatic GG provisioning
  source secrets.env
  gg_run greengrass_demo_provisioning provision
}

function start_thing() {
  # Start an automatically provisioned GG thing
  source secrets.env
  gg_run greengrass_demo_run run "-d -p 1441:1441 -p 1442:1442"
}

function manual_gg_run() {
  # Manual provision and start a GG thing

  if [ "$1" == "init" ]; then
    echo "Cleaning GG_HOME volume if exists"
    if docker volume inspect GG_HOME >/dev/null 2>&1; then
      if docker container inspect greengrass_demo_run >/dev/null 2>&1; then
        docker container rm greengrass_demo_run >/dev/null
      fi
      docker volume rm GG_HOME >/dev/null
    fi
  fi

  source secrets.env
  gg_run greengrass_demo_run manual_run "-d -p 1441:1441 -p 1442:1442"
}

function run_demo() {
  # Start the demo using automatic GG provisioning
  parsec_run
  provision_thing
  start_thing
  docker logs -f greengrass_demo_run
}

function run_manual_demo() {
  # Start the demo using manual GG provisioning
  parsec_run
  manual_gg_run ${1}
  docker logs -f greengrass_demo_run
}

function run_manual_demo_tpm() {
  # Start Parsec with TPM provider and the demo using manual GG provisioning
  parsec_run tpm
  manual_gg_run ${1}
  docker logs -f greengrass_demo_run
}

function build_gg() {
  # Build GreenGrass images

  echo "Starting build GreenGrass images ..."
  build_greengrass_patched
  build_greengrass_with_provider
  echo "Build Done."
}

function build() {
  # Build Parsec with Mbed-Crypto provider and GG docker images

  echo "Starting build Parsec image..."
  build_parsec_image
  echo "Build Done."
  build_gg
}

function build_tpm() {
  # Build Parsec with TPM provider and GG docker images

  echo "Starting build Parsec TPM image..."
  build_parsec_tpm_image
  echo "Build Done."
  build_gg
}

if [ -z "${1}" ]; then
  build
  run_demo
else
  ${@}
fi
