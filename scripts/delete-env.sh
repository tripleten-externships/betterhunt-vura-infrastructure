#!/bin/bash

# AWS CloudFormation Stack Deletion Script for Single-Environment Deployments
# Usage: ./scripts/delete-env.sh <environment> [project-name] [region]
# Environment options: dev, staging, prod

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
    echo "Usage: $0 <environment> [project-name] [region]"
    echo ""
    echo "Arguments:"
    echo "  environment  Target environment to delete"
    echo "              Options: dev, staging, prod"
    echo "  project-name  Name of the project (optional)"
    echo "              Default: my-app-<environment>"
    echo "  region      AWS region (optional)"
    echo "              Default: us-east-1"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 staging my-custom-app"
    echo "  $0 prod my-app us-west-2"
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
STACK_NAME="${PROJECT_NAME}"

print_header "=== AWS CloudFormation Stack Deletion ==="
print_status "Environment: ${ENVIRONMENT}"
print_status "Project Name: ${PROJECT_NAME}"
print_status "Stack Name: ${STACK_NAME}"
print_status "Region: ${REGION}"

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null || echo "")

if [[ -z "$STACK_EXISTS" ]]; then
    print_error "Stack does not exist: ${STACK_NAME}"
    exit 1
fi

print_warning "WARNING"
print_warning "This action will DELETE all resources created by the CloudFormation stack:"
print_warning "- S3 buckets (and all their contents)"
print_warning "- CloudFront distributions"
print_warning "- VPC and networking resources"
print_warning "- RDS databases"
print_warning "- ECS resources"
print_warning "- API Gateway resources"
print_warning "- IAM roles and policies"
print_warning "This action CANNOT be undone!"

echo ""
read -p "Type the stack name '${STACK_NAME}' to confirm deletion: " -r CONFIRM

if [[ "$CONFIRM" != "$STACK_NAME" ]]; then
    print_status "Deletion cancelled."
    exit 0
fi

# Clean up S3 buckets first (needed to avoid deletion failure)
print_header "Emptying S3 buckets (if any)"

# Try to get bucket names from stack outputs
BUCKETS=()

# Frontend buckets
STAGING_BUCKET=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='StagingBucketName'].OutputValue" --output text 2>/dev/null || echo "")
if [[ ! -z "$STAGING_BUCKET" && "$STAGING_BUCKET" != "None" ]]; then
    BUCKETS+=("$STAGING_BUCKET")
fi

PROD_BUCKET=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='ProductionBucketName'].OutputValue" --output text 2>/dev/null || echo "")
if [[ ! -z "$PROD_BUCKET" && "$PROD_BUCKET" != "None" ]]; then
    BUCKETS+=("$PROD_BUCKET")
fi

STORYBOOK_BUCKET=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='StorybookBucketName'].OutputValue" --output text 2>/dev/null || echo "")
if [[ ! -z "$STORYBOOK_BUCKET" && "$STORYBOOK_BUCKET" != "None" ]]; then
    BUCKETS+=("$STORYBOOK_BUCKET")
fi

# Empty each bucket
for BUCKET in "${BUCKETS[@]}"; do
    if [[ ! -z "$BUCKET" ]]; then
        print_status "Emptying bucket: ${BUCKET}"
        
        # Check if bucket exists and is accessible
        if aws s3 ls "s3://${BUCKET}" &> /dev/null; then
            # Empty the bucket
            aws s3 rm "s3://${BUCKET}" --recursive --region $REGION
            print_status "Bucket emptied: ${BUCKET}"
        else
            print_warning "Bucket not accessible or does not exist: ${BUCKET}"
        fi
    fi
done

# If this is a staging or prod environment, clean up related resources
if [[ "$ENVIRONMENT" != "dev" ]]; then
    # Delete Secrets Manager secret
    print_status "Checking for database credentials secret..."
    SECRET_NAME="${STACK_NAME}-db-credentials"
    
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region $REGION &> /dev/null; then
        print_status "Deleting secret: ${SECRET_NAME}"
        aws secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery \
            --region $REGION
    else
        print_status "No secret found: ${SECRET_NAME}"
    fi
    
    # Delete SSM parameter
    print_status "Checking for container image parameter..."
    PARAM_NAME="/app/${STACK_NAME}/container-image"
    
    if aws ssm get-parameter --name "$PARAM_NAME" --region $REGION &> /dev/null; then
        print_status "Deleting parameter: ${PARAM_NAME}"
        aws ssm delete-parameter \
            --name "$PARAM_NAME" \
            --region $REGION
    else
        print_status "No parameter found: ${PARAM_NAME}"
    fi
fi

# Delete the stack
print_header "Deleting CloudFormation stack: ${STACK_NAME}"

aws cloudformation delete-stack \
    --stack-name $STACK_NAME \
    --region $REGION

print_status "Stack deletion initiated"
print_status "Waiting for stack deletion to complete (this may take 15-30 minutes)..."

aws cloudformation wait stack-delete-complete \
    --stack-name $STACK_NAME \
    --region $REGION

if [ $? -eq 0 ]; then
    print_header "Stack deletion completed successfully!"
else
    print_error "Stack deletion failed or timed out. Check AWS CloudFormation Console for details."
    print_error "You may need to manually delete resources that failed to delete."
fi

print_status "Environment ${ENVIRONMENT} has been deleted." 