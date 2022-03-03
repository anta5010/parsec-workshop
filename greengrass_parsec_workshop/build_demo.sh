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

function update_git() {
  git submodule update --init --recursive
}

function build_greengrass_patched() {
pushd ./aws-greengrass-parsec-provider/parsec-greengrass-run-config/docker/
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

  # shellcheck disable=SC2086
  docker run ${3} \
         --name "${1}" \
         -e GG_THING_NAME="${GG_THING_NAME}" \
         -e GG_ADDITIONAL_CMD_ARGS="--trusted-plugin /provider.jar --tes-role-name Proj-AntA-GreengrassV2TokenExchangeRole --tes-role-alias-name Proj-AntA-GreengrassCoreTokenExchangeRoleAlias " \
         -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
         -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
         -e AWS_REGION="${AWS_REGION}" \
         -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" \
         -v GG_PARSEC_SOCK:/run/parsec \
         -v GG_HOME:/home/ggc_user \
         parallaxsecond/greengrass_demo:latest "${2}"
}

function prepare_demo() {
  parsec_run
  source secrets.env
  gg_run greengrass_demo_provisioning provision
}

function run_demo() {
  source secrets.env
  gg_run greengrass_demo_run run "-d -p 1441:1441 -p 1442:1442"
  docker logs -f greengrass_demo_run
}

function build() {
  echo "Starting build ..."
  build_greengrass_patched
  build_parsec_containers
  build_greengrass_with_provider
  echo "Build Done."
}
if [ "${1}" == "" ]; then
  build
  prepare_demo
  run_demo
else
  ${1}
fi
