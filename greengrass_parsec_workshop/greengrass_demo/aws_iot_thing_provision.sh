#!/bin/bash

# Manually provision an AWS GreenGrass IOT thing.
# This script:
# - Creates an AWS IOT thing and its group
# - Use parsec-tool to create an RSA signiture key and an CSR
# - Creates a certificate from the CSR
# - Creates all the required AWS IAM and IOT policies, roles, role aliases and
#   makes attachments
# - Generates GreenGrass config file
# The script follows https://docs.aws.amazon.com/greengrass/v2/developerguide/manual-installation.html

# There are mandatory and optional ENV variables used by thhis script
# Mandatory:
# - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY - AWS access settings
# - AWS_REGION - The AWS region where the IOT thing created
# - GG_THING_NAME - AWS IOT thing name
# Optional:
# - AWS_SESSION_TOKEN - AWS session token if used.
# - AWS_BOUNDARY_POLICY - A boundary policy name for IAM roles if required.
# - GG_THING_GROUP - IOT group name for the thing.
#   default: ${AWS_ROLE_PREFIX}GreengrassQuickStartGroup
# - AWS_ROLE_PREFIX - A prefix added to all created policies and roles names
#   default: empty

set -e

for mandatory_env in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION GG_THING_NAME; do
  if [ "${!mandatory_env}" == "" ]; then
    echo "The env variable ${mandatory_env} needs to be set"
    exit 255
  fi
done

export AWS_DEFAULT_REGION=${AWS_REGION}
AWS_ID=$(aws sts get-caller-identity --query "Account" --output text)

if [ -z "$AWS_ID" ]; then
  echo "Can't get AWS Account ID. Check that:"
  echo " - aws cli tool installed and"
  echo " - AWS_ACCESS_* env variables have not expired"
  exit 1
fi

if [ -n "${AWS_ROLE_PREFIX}" ]; then
  AWS_PREFIX="${AWS_ROLE_PREFIX}-"
fi

echo "Create an AWS IoT thing and its group"
# https://docs.aws.amazon.com/greengrass/v2/developerguide/manual-installation.html#create-iot-thing

GG_THING_GROUP=${GG_THING_GROUP:-${AWS_PREFIX}GreengrassQuickStartGroup}

aws iot create-thing-group --thing-group-name ${GG_THING_GROUP}
aws iot create-thing --thing-name ${GG_THING_NAME}
aws iot add-thing-to-thing-group --thing-name ${GG_THING_NAME} --thing-group-name ${GG_THING_GROUP}

echo "Create the thing certificate using an RSA key created with parsec-tool"
# https://docs.aws.amazon.com/greengrass/v2/developerguide/manual-installation.html#create-thing-certificate

# Create an RSA signature key if it doesn't exist
if ! parsec-tool export-public-key --key-name ${GG_THING_NAME} >/dev/nul 2>&1; then
  parsec-tool create-rsa-key -s --key-name ${GG_THING_NAME}
fi
parsec-tool create-csr --key-name ${GG_THING_NAME} --cn "${GG_THING_NAME}" >${GG_THING_NAME}-devicekey.csr

# Create a new certificate
gg_cert_arn=$(aws iot create-certificate-from-csr --set-as-active \
        --certificate-signing-request=file://${GG_THING_NAME}-devicekey.csr \
        --certificate-pem-outfile /home/ggc_user/device.pem.crt --output text --query "certificateArn")
rm -f ${GG_THING_NAME}-devicekey.csr

echo "Configure the thing certificate"
# https://docs.aws.amazon.com/greengrass/v2/developerguide/manual-installation.html#configure-thing-certificate

# Delete old certificates if exist
for cert in $(aws iot list-thing-principals --thing-name ${GG_THING_NAME} --query "principals" --output text); do
  aws iot detach-thing-principal --thing-name ${GG_THING_NAME} --principal $cert

  cert_id=${cert##*/}
  aws iot update-certificate --certificate-id $cert_id --new-status INACTIVE
  aws iot delete-certificate --force-delete --certificate-id $cert_id
done

aws iot attach-thing-principal --thing-name ${GG_THING_NAME} --principal ${gg_cert_arn}

if ! aws iot get-policy --policy-name ${AWS_PREFIX}GreengrassV2IoTThingPolicy 2>/dev/null 1>&2; then

  cat <<EOF >greengrass-v2-iot-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:Publish",
        "iot:Subscribe",
        "iot:Receive",
        "iot:Connect",
        "greengrass:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

  aws iot create-policy --policy-name ${AWS_PREFIX}GreengrassV2IoTThingPolicy \
          --policy-document file://greengrass-v2-iot-policy.json
  rm -f greengrass-v2-iot-policy.json
fi

aws iot attach-policy --policy-name ${AWS_PREFIX}GreengrassV2IoTThingPolicy \
        --target ${gg_cert_arn}

echo "Create a token exchange role"
# https://docs.aws.amazon.com/greengrass/v2/developerguide/manual-installation.html#create-token-exchange-role

if [ -n "${AWS_BOUNDARY_POLICY}" ]; then
  PERMISSION_BOUNDARY="--permissions-boundary arn:aws:iam::${AWS_ID}:policy/${AWS_BOUNDARY_POLICY}"
fi

if ! aws iam get-role --role-name ${AWS_PREFIX}GreengrassV2TokenExchangeRole 2>/dev/null 1>&2; then
  cat <<EOF >device-role-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "credentials.iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  aws iam create-role --role-name ${AWS_PREFIX}GreengrassV2TokenExchangeRole \
          --assume-role-policy-document file://device-role-trust-policy.json \
          ${PERMISSION_BOUNDARY}
  rm -f device-role-trust-policy.json
fi

if ! aws iam get-policy --policy-arn arn:aws:iam::${AWS_ID}:policy/${AWS_PREFIX}GreengrassV2TokenExchangeRoleAccess 2>/dev/null 1>&2; then
  cat <<EOF >device-role-access-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:DescribeCertificate",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "s3:GetBucketLocation"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  aws iam create-policy --policy-name ${AWS_PREFIX}GreengrassV2TokenExchangeRoleAccess \
                        --policy-document file://device-role-access-policy.json
  rm -f device-role-access-policy.json
fi

aws iam attach-role-policy --role-name ${AWS_PREFIX}GreengrassV2TokenExchangeRole \
        --policy-arn arn:aws:iam::${AWS_ID}:policy/${AWS_PREFIX}GreengrassV2TokenExchangeRoleAccess

if ! aws iot describe-role-alias --role-alias ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAlias 2>/dev/null 1>&2; then
  aws iot create-role-alias --role-alias ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAlias \
          --role-arn arn:aws:iam::${AWS_ID}:role/${AWS_PREFIX}GreengrassV2TokenExchangeRole
fi

role_arn=$(aws iot describe-role-alias --role-alias ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAlias \
           --query "roleAliasDescription.roleArn")

if ! aws iot get-policy --policy-name ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAliasPolicy 2>/dev/null 1>&2; then
  cat <<EOF >greengrass-v2-iot-role-alias-policy.json
{
  "Version":"2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:AssumeRoleWithCertificate",
      "Resource": ${role_arn}
    }
  ]
}
EOF

  aws iot create-policy --policy-name ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAliasPolicy \
          --policy-document file://greengrass-v2-iot-role-alias-policy.json
  rm -f greengrass-v2-iot-role-alias-policy.json
fi

aws iot attach-policy --policy-name ${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAliasPolicy \
        --target ${gg_cert_arn}

echo "Create GreenGrass config file"

iot_endpoint=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --output text)
cred_endpoint=$(aws iot describe-endpoint --endpoint-type iot:CredentialProvider --output text)

curl https://www.amazontrust.com/repository/AmazonRootCA1.pem \
     >/home/ggc_user/AmazonRootCA1.pem 2>/dev/null

cat <<EOF >/greengrass/config.yml
system:
  certificateFilePath: "parsec:import=/home/ggc_user/device.pem.crt;object=${GG_THING_NAME};type=cert"
  privateKeyPath: "parsec:object=${GG_THING_NAME};type=private"
  rootCaPath: "/home/ggc_user/AmazonRootCA1.pem"
  rootpath: ""
  thingName: "${GG_THING_NAME}"
services:
  aws.greengrass.Nucleus:
    componentType: "NUCLEUS"
    configuration:
      awsRegion: "${AWS_DEFAULT_REGION}"
      iotRoleAlias: "${AWS_PREFIX}GreengrassCoreTokenExchangeRoleAlias"
      iotDataEndpoint: "${iot_endpoint}"
      iotCredEndpoint: "${cred_endpoint}"
  aws.greengrass.crypto.ParsecProvider:
    configuration:
      name: "greengrass-parsec-plugin"
      parsecSocket: "/run/parsec/parsec.sock"
EOF
