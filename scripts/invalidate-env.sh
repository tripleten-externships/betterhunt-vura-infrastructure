#!/bin/bash

# CloudFront Cache Invalidation Script for Single-Environment Deployments
# Usage: ./scripts/invalidate-env.sh <environment> [project-name] [region] [paths]
# Environment options: dev, staging, prod
# Default paths: /*

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

show_help() {
    echo "Usage: $0 <environment> [project-name] [region] [paths]"
    echo ""
    echo "Arguments:"
    echo "  environment  Target environment to invalidate"
    echo "              Options: dev, staging, prod"
    echo "  project-name  Name of the project (optional)"
    echo "              Default: my-app-<environment>"
    echo "  region      AWS region (optional)"
    echo "              Default: us-east-1"
    echo "  paths       CloudFront paths to invalidate (optional)"
    echo "              Default: /*"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 staging my-custom-app"
    echo "  $0 prod my-app us-west-2 \"/images/*\""
}

if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    show_help
    exit 0
fi

# Check if environment is valid
ENVIRONMENT=${1}
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment. Must be: dev, staging, or prod"
    echo ""
    show_help
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Parse arguments
PROJECT_NAME=${2:-"my-app-$ENVIRONMENT"}
REGION=${3:-"us-east-1"}
PATHS=${4:-"/*"}
STACK_NAME="${PROJECT_NAME}"

print_header "=== CloudFront Cache Invalidation ==="
print_status "Environment: ${ENVIRONMENT}"
print_status "Project Name: ${PROJECT_NAME}"
print_status "Stack Name: ${STACK_NAME}"
print_status "Region: ${REGION}"
print_status "Paths to Invalidate: ${PATHS}"

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null || echo "")

if [[ -z "$STACK_EXISTS" ]]; then
    print_error "Stack does not exist: ${STACK_NAME}"
    exit 1
fi

# Determine which distribution ID to use based on environment
if [[ "$ENVIRONMENT" == "dev" ]]; then
    # Dev environment uses staging distribution
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='StagingDistributionId'].OutputValue" \
        --output text)
elif [[ "$ENVIRONMENT" == "staging" ]]; then
    # Staging environment uses staging distribution
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='StagingDistributionId'].OutputValue" \
        --output text)
elif [[ "$ENVIRONMENT" == "prod" ]]; then
    # Production environment uses production distribution
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='ProductionDistributionId'].OutputValue" \
        --output text)
fi

if [[ -z "$DISTRIBUTION_ID" ]]; then
    print_error "Could not find CloudFront distribution ID for ${ENVIRONMENT} environment"
    print_error "Make sure the stack has been deployed successfully and the environment has a CloudFront distribution"
    exit 1
fi

print_status "Found CloudFront distribution ID: ${DISTRIBUTION_ID}"

# Create invalidation
print_status "Creating invalidation for paths: ${PATHS}"

INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "$PATHS" \
    --region $REGION \
    --query "Invalidation.Id" \
    --output text)

print_status "Invalidation created with ID: ${INVALIDATION_ID}"
print_status "Waiting for invalidation to complete..."

# Wait for invalidation to complete
aws cloudfront wait invalidation-completed \
    --distribution-id $DISTRIBUTION_ID \
    --id $INVALIDATION_ID \
    --region $REGION

print_status "Invalidation completed successfully for ${ENVIRONMENT} environment" 