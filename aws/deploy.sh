#!/bin/bash
# Deploy FreeTAKServer 2.x CloudFormation stack
# Usage: ./deploy.sh [stack-name] [region]

set -e

STACK="${1:-tak-server}"
REGION="${2:-ca-central-1}"
TEMPLATE="$(dirname "$0")/cloudformation.yaml"

echo "Deploying $STACK to $REGION ..."

aws cloudformation deploy \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK" \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    KeyPairName="${TAK_KEY_PAIR:?Set TAK_KEY_PAIR}" \
    HostedZoneId="${TAK_HOSTED_ZONE:?Set TAK_HOSTED_ZONE}" \
    VpcId="${TAK_VPC_ID:?Set TAK_VPC_ID}" \
    SubnetId="${TAK_SUBNET_ID:?Set TAK_SUBNET_ID}" \
    AllowedIP="${TAK_ALLOWED_IP:-0.0.0.0/0}" \
    DomainName="${TAK_DOMAIN:-tak.takaware.ca}" \
    FTSImageTag="${TAK_FTS_TAG:-master}"

echo ""
echo "Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
