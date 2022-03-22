#!/bin/bash
set -e
pushd $(dirname $0)
md5_cmd=md5

PARSEC_VERSION="1.0.0rc2"

if ! test -x /sbin/md5; then
  md5_cmd=md5sum
fi

if [ -z "$GG_THING_NAME" ]; then
  GG_THING_NAME=$(id -un)-GG-parsec
  if test -e /etc/hostname; then
    GG_THING_NAME=$(cat /etc/hostname)-GG-parsec
  fi

  # GreenGrass think name must not contain dots
  GG_THING_NAME=${GG_THING_NAME//\./_}
fi

function update_git() {
  git submodule update --init --recursive
}

function build_greengrass_patched() {
  # Build GreenGrass docker images using key-op-prototype branch of AWS SDKs
  pushd ./parsec-greengrass-run-config/docker/
  docker build . \
        --tag parallaxsecond/greengrass_patched:latest \
        --progress plain
  popd
}

function build_parsec_containers() {
  # Build Parsec+Mbed-Crypto docker image
  pushd ./parsec-testcontainers/
  ./build.sh
  popd
}

function build_parsec_tpm_containers() {
  # Build Parsec+TPM docker image

  pushd ./parsec-testcontainers/
  ./build.sh parsec_tpm
  popd
}

function build_greengrass_with_provider() {
  # Build the demo docker image including Parsec GG provider

  docker build . -f greengrass_demo/Dockerfile --tag parallaxsecond/greengrass_demo:latest  --progress plain
}

function parsec_run() {
  # Run a container from Parsec+Mbed-Crypto provider image if exists

  if docker image inspect parallaxsecond/parsec:${PARSEC_VERSION} >/dev/null; then
    docker rm -f parsec_docker_run 2> /dev/null
    docker run -d --name parsec_docker_run \
          -ti \
          -v GG_PARSEC_STORE:/var/lib/parsec/mappings \
          -v GG_PARSEC_SOCK:/run/parsec \
           parallaxsecond/parsec:${PARSEC_VERSION}
  else
    echo "Parsec image is missing. Build it if Parsec running in a container is required"
  fi
}

function parsec_tpm_run() {
  # Run a container from Parsec+TPM provider image if exists
  if docker image inspect parallaxsecond/parsec:${PARSEC_VERSION} >/dev/null; then
    docker rm -f parsec_docker_run 2> /dev/null
    docker run -d --name parsec_docker_run \
          -ti \
          -v GG_PARSEC_SOCK:/run/parsec \
          --device /dev/tpm0 \
          --device /dev/tpmrm0 \
           parallaxsecond/parsec:${PARSEC_VERSION}tpm
  else
    echo "Parsec image is missing. Build it if Parsec running in a container is required"
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

  # Check if we run Parsec in a container
  if docker volume inspect GG_PARSEC_SOCK >/dev/null 2>&1; then
    # Parsec is running in a container
    PARSEC_VOLUME="GG_PARSEC_SOCK:/run/parsec"
  else
    # Parsec is running on host
    PARSEC_VOLUME="/run/parsec:/run/parsec"
  fi

  # shellcheck disable=SC2086
  docker run ${3} \
         --name "${1}" \
         -e GG_THING_NAME="${GG_THING_NAME}" \
         -e GG_THING_GROUP="${GG_THING_GROUP}" \
         -e GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS}" \
         -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
         -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
         -e AWS_REGION="${AWS_REGION}" \
         -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" \
         -e AWS_ROLE_PREFIX="${AWS_ROLE_PREFIX}" \
         -e AWS_BOUNDARY_POLICY="${AWS_BOUNDARY_POLICY}" \
         -v ${PARSEC_VOLUME} \
         -v GG_HOME:/home/ggc_user \
         parallaxsecond/greengrass_demo:latest "${2}"
}

function provision_thing() {
  # Automatic GG provisioning

  # Clean GG_HOME volume if exists
  if docker volume inspect GG_HOME >/dev/null 2>&1; then
    docker volume rm GG_HOME
  fi

  source secrets.env
  gg_run greengrass_demo_provisioning provision
}

function start_thing() {
  # Start an automatically provisioned GG thing
  source secrets.env
  gg_run greengrass_demo_run run "-d -p 1441:1441 -p 1442:1442"
}

function manual_run() {
  # Manual provision and start a GG thing

  # Clean GG_HOME volume if exists
  if docker volume inspect GG_HOME >/dev/null 2>&1; then
    docker volume rm GG_HOME
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
  manual_run
  docker logs -f greengrass_demo_run
}

function run_manual_demo_tpm() {
  # Start Parsec with TPM provider and the demo using manual GG provisioning
  parsec_tpm_run
  manual_run
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
  # Build Parsec image with Mbed-Crypto provider and GG images

  echo "Starting build Parsec images..."
  build_parsec_containers
  echo "Build Done."
  build_gg
}

function build_tpm() {
  # Build Parsec image with TPM provider and GG images

  echo "Starting build Parsec TPM images..."
  build_parsec_tpm_containers
  echo "Build Done."
  build_gg
}

if [ -z "${1}" ]; then
  build
  run_demo
else
  ${@}
fi
