#!/bin/bash

# AWS CloudFormation Deployment Script for Single-Environment Deployments
# Usage: ./scripts/deploy-env.sh <environment> [project-name] [region]
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
    echo "  environment  Target environment to deploy"
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

# Environment-specific parameter file
PARAM_FILE="parameters/environment/${ENVIRONMENT}.json"

# Check if parameter file exists
if [[ ! -f "$PARAM_FILE" ]]; then
    print_error "Environment parameter file not found: $PARAM_FILE"
    echo ""
    print_status "Creating directory structure if needed..."
    mkdir -p parameters/environment
    
    print_error "Please create environment parameter files first:"
    echo "  parameters/environment/dev.json"
    echo "  parameters/environment/staging.json"
    echo "  parameters/environment/prod.json"
    exit 1
fi

# Check if template exists
TEMPLATE_FILE="templates/main.yaml"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Display deployment information
print_header "=== AWS CloudFormation Deployment ==="
print_status "Environment: ${ENVIRONMENT}"
print_status "Project Name: ${PROJECT_NAME}"
print_status "Stack Name: ${STACK_NAME}"
print_status "Region: ${REGION}"
print_status "Parameter File: ${PARAM_FILE}"
print_status "Template File: ${TEMPLATE_FILE}"

# Set up database credentials if needed
if [[ "$ENVIRONMENT" != "dev" ]]; then
    print_header "Checking Database Credentials"
    
    # Check if the secret already exists
    SECRET_EXISTS=$(aws secretsmanager list-secrets --query "SecretList[?Name=='${STACK_NAME}-db-credentials'].Name" --output text --region $REGION || echo "")

    if [[ -z "$SECRET_EXISTS" ]]; then
        print_status "Creating database credentials secret..."
        
        # Generate a random password
        DB_PASSWORD=$(openssl rand -base64 16)
        
        # Create the secret
        aws secretsmanager create-secret \
            --name "${STACK_NAME}-db-credentials" \
            --description "Database credentials for ${STACK_NAME}" \
            --secret-string "{\"username\":\"dbadmin\",\"password\":\"$DB_PASSWORD\"}" \
            --region $REGION
            
        print_status "Secret created successfully"
    else
        print_status "Database credentials secret already exists"
    fi
    
    # Check/create container image parameter
    print_header "Checking Container Image Parameter"
    
    # Check if the parameter already exists
    PARAM_EXISTS=$(aws ssm get-parameter --name "/app/${STACK_NAME}/container-image" --query "Parameter.Name" --output text --region $REGION 2>/dev/null || echo "")

    if [[ -z "$PARAM_EXISTS" ]]; then
        print_status "Creating SSM parameter for container image..."
        
        # For demo, we'll use a public nginx image
        CONTAINER_IMAGE="public.ecr.aws/nginx/nginx:latest"
        
        aws ssm put-parameter \
            --name "/app/${STACK_NAME}/container-image" \
            --type "String" \
            --value "$CONTAINER_IMAGE" \
            --description "Container image for ${STACK_NAME}" \
            --region $REGION
            
        print_status "Parameter created successfully"
    else
        print_status "Container image parameter already exists"
    fi
fi

# Show deployment preview
print_header "=== Configuration Preview ==="
if command -v jq &> /dev/null; then
    echo "Parameters:"
    jq -r '.[] | "  \(.ParameterKey): \(.ParameterValue)"' "$PARAM_FILE"
else
    print_warning "jq not installed - parameter preview not available"
fi

echo ""
read -p "Continue with deployment? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled."
    exit 0
fi

# Validate template
print_status "Validating CloudFormation template..."
if aws cloudformation validate-template --template-body file://$TEMPLATE_FILE --region $REGION > /dev/null; then
    print_status "Template validation successful"
else
    print_error "Template validation failed"
    exit 1
fi

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null || echo "")

if [[ -z "$STACK_EXISTS" ]]; then
    # Create stack
    print_header "Creating new stack: ${STACK_NAME}"
    
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAM_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    print_status "Stack creation initiated"
    print_status "Waiting for stack creation to complete (this may take 15-20 minutes)..."
    
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION
    
    if [ $? -eq 0 ]; then
        print_header "Stack creation completed successfully!"
    else
        print_error "Stack creation failed or timed out. Check AWS CloudFormation Console for details."
    fi
else
    # Update stack
    print_header "Updating existing stack: ${STACK_NAME}"
    
    aws cloudformation update-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAM_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION || {
            if [[ $? -eq 255 && $REPLY =~ "No updates are to be performed" ]]; then
                print_status "No updates are needed for the stack"
                exit 0
            else
                print_error "Stack update failed"
                exit 1
            fi
        }
    
    print_status "Stack update initiated"
    print_status "Waiting for stack update to complete..."
    
    aws cloudformation wait stack-update-complete --stack-name $STACK_NAME --region $REGION
    
    if [ $? -eq 0 ]; then
        print_header "Stack update completed successfully!"
    else
        print_error "Stack update failed or timed out. Check AWS CloudFormation Console for details."
    fi
fi

# Display stack outputs
print_header "Stack Outputs:"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs" \
    --region $REGION \
    --output table

print_status "Deployment of ${ENVIRONMENT} environment completed."
print_status "You can now deploy your application to this environment." 