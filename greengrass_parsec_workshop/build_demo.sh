#!/bin/bash
set -e
pushd $(dirname $0)
md5_cmd=md5

if ! test -x /sbin/md5; then
  md5_cmd=md5sum
fi

if [ -z "$GG_THING_NAME" ]; then
  GG_THING_NAME=$(id -un)-greengrass-parsec
  if test -e /etc/hostname; then
    GG_THING_NAME=$(cat /etc/hostname)-greengrass-parsec
  fi
fi
GG_THING_GROUP=${GG_THING_GROUP:-GreengrassQuickStartGroup}

function update_git() {
  git submodule update --init --recursive
}

function build_greengrass_patched() {
  pushd ./parsec-greengrass-run-config/docker/
  docker build . \
        --tag parallaxsecond/greengrass_patched:latest \
        --progress plain
  popd
}

function build_parsec_containers() {
  pushd ./parsec-testcontainers/
  ./build.sh
  popd
}

function build_greengrass_with_provider() {
  docker build . -f greengrass_demo/Dockerfile --tag parallaxsecond/greengrass_demo:latest  --progress plain
}

function parsec_run() {
    docker rm -f parsec_docker_run 2> /dev/null
    docker run -d --name parsec_docker_run \
          -ti \
          -v GG_PARSEC_STORE:/var/lib/parsec/mappings \
          -v GG_PARSEC_SOCK:/run/parsec \
           parallaxsecond/parsec:0.8.1
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
  if [ -n "${AWS_ROLE_PREFIX}" ]; then
    GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS} --tes-role-name ${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRole"
    GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS} --tes-role-alias-name ${AWS_ROLE_PREFIX}-GreengrassCoreTokenExchangeRoleAlias"
  fi

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
         -v ${PARSEC_VOLUME} \
         -v GG_HOME:/home/ggc_user \
         parallaxsecond/greengrass_demo:latest "${2}"
}

function provision_thing() {
  source secrets.env
  gg_run greengrass_demo_provisioning provision
}

function start_thing() {
  source secrets.env
  gg_run greengrass_demo_run run "-d -p 1441:1441 -p 1442:1442"
}

function run_demo() {
  parsec_run

  provision_thing
  start_thing

  docker logs -f greengrass_demo_run
}

function build() {
  echo "Starting build ..."
  build_greengrass_patched
  build_parsec_containers
  build_greengrass_with_provider
  echo "Build Done."
}

if [ -z "${1}" ]; then
  build
  run_demo
else
  ${@}
fi
