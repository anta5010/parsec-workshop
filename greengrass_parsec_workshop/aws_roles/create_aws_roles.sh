#!/bin/bash

# Create AWS roles/policies used for the GreenGrass demo.

# This scripts can be used if the default GG roles/policies
# can't be created because of AWS account limitations where
# a special prefix is required for roles/policies names.

for mandatory_env in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_ROLE_PREFIX; do
  if [ "${!mandatory_env}" == "" ]; then
    echo "The env variable ${mandatory_env} needs to be set"
    exit 255
  fi
done

AWS_ID=$(aws sts get-caller-identity --query "Account" --output text)

if [ -z "$AWS_ID" ]; then
  echo "Can't get AWS Account ID. Check that:"
  echo " - aws cli tool installed and"
  echo " - AWS_ACCESS_* env variables have not expired"
  exit 1
fi

aws iam create-role --role-name ${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRole \
    --assume-role-policy-document file://device-role-trust-policy.json \
    --permissions-boundary arn:aws:iam::{$AWS_ID}:policy/ProjAdminsPermBoundaryv2

aws iam create-policy --policy-name ${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRoleAccess \
                      --policy-document file://device-role-access-policy.json

aws iam attach-role-policy --role-name ${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRole \
        --policy-arn arn:aws:iam::{$AWS_ID}:policy/${AWS_ROLE_PREFIX}-GreengrassV2TokenExchangeRoleAccess

aws iot create-role-alias --role-alias ${AWS_ROLE_PREFIX}-GreengrassCoreTokenExchangeRoleAlias \
        --role-arn arn:aws:iam::{$AWS_ID}:role/Proj-AntA-GreengrassV2TokenExchangeRole
