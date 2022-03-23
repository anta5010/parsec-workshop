#!/bin/bash
set -e

case "${1}" in
/bin/*sh)
  exec "$@"
  ;;
manual_run)
  # Run the GG think with manual provisionning
  :
  ;;
*)
  if [ -n "${AWS_ROLE_PREFIX}" ]; then
    export GG_THING_GROUP=${GG_THING_GROUP:-${AWS_ROLE_PREFIX}-GreengrassQuickStartGroup}
    GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS} --tes-role-name ${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRole"
    export GG_ADDITIONAL_CMD_ARGS="${GG_ADDITIONAL_CMD_ARGS} --tes-role-alias-name ${AWS_ROLE_PREFIX}-GreengrassCoreTokenExchangeRoleAlias"
  fi
  /greengrass/start.sh $@
  exit 0
esac

if [ "${2}" == "debug" ]; then
  JAVA_OPTS="${JAVA_OPTS} -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5005"
  echo "using Debug config ${JAVA_OPTS}"
fi

# Manual provisioning
if ! /greengrass/aws_iot_thing_provision.sh; then
  echo "Failed to manually provission the GG thing"
  exit 255
fi

set -x
# shellcheck disable=SC2086

CMD="java ${JAVA_OPTS}
  -jar /greengrass/lib/Greengrass.jar
  --aws-region ${AWS_REGION}
  --provision false
  --root /home/ggc_user
  --component-default-user ggc_user:ggc_group
  --init-config /home/ggc_user/generated_config.yml
  --start true
  ${GG_ADDITIONAL_CMD_ARGS}
  "

if [ "${GG_KEEP_RUNNING}" == "true" ]; then
  # shellcheck disable=SC2090
  ${CMD}
  exec sleep 10000
else
  # shellcheck disable=SC2086
  exec ${CMD}
fi
