#!/bin/bash

# Script to package and upload the CloudFormation templates to S3
# Usage: ./scripts/package-templates.sh [bucket-name] [region]

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
    echo "Usage: $0 [bucket-name] [region]"
    echo ""
    echo "Arguments:"
    echo "  bucket-name  Name of the S3 bucket to store templates (optional)"
    echo "              Default: cloudformation-templates-<account-id>"
    echo "  region      AWS region (optional)"
    echo "              Default: us-east-1"
    echo ""
    echo "Example:"
    echo "  $0"
    echo "  $0 my-templates-bucket us-west-2"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
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

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Parse arguments
REGION=${2:-"us-east-1"}
BUCKET_NAME=${1:-"cloudformation-templates-${AWS_ACCOUNT_ID}"}

# Display information
print_header "=== CloudFormation Template Packaging ==="
print_status "S3 Bucket: ${BUCKET_NAME}"
print_status "Region: ${REGION}"

# Check if bucket exists and create it if needed
if ! aws s3api head-bucket --bucket $BUCKET_NAME --region $REGION 2>/dev/null; then
    print_status "Bucket does not exist. Creating bucket..."
    
    # Handle bucket creation differently based on region
    if [ "$REGION" == "us-east-1" ]; then
        # For us-east-1, don't specify location constraint
        aws s3api create-bucket \
            --bucket $BUCKET_NAME \
            --region $REGION
    else
        # For other regions, specify location constraint
        aws s3api create-bucket \
            --bucket $BUCKET_NAME \
            --region $REGION \
            --create-bucket-configuration LocationConstraint=$REGION
    fi
    
    # Wait for bucket to be created
    aws s3api wait bucket-exists --bucket $BUCKET_NAME --region $REGION
    print_status "Bucket created successfully."
    
    # Enable versioning on the bucket
    aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled \
        --region $REGION
    
    print_status "Bucket versioning enabled."
else
    print_status "Bucket already exists."
fi

# Create directory structure in S3 bucket
print_status "Creating directory structure in S3 bucket..."

# List of directories to create in S3
DIRECTORIES=(
    "templates/"
    "templates/networking/"
    "templates/storage/"
    "templates/frontend/"
    "templates/backend/"
    "templates/iam/"
)

# Create empty objects to represent directories
for dir in "${DIRECTORIES[@]}"; do
    aws s3api put-object \
        --bucket $BUCKET_NAME \
        --key $dir \
        --region $REGION
done

print_status "Directory structure created in S3 bucket."

# Upload templates to S3
print_header "Uploading Templates to S3"

# List of templates to upload
TEMPLATES=(
    "templates/main.yaml:templates/main.yaml"
    "templates/networking/vpc.yaml:templates/networking/vpc.yaml"
    "templates/networking/security-groups.yaml:templates/networking/security-groups.yaml"
    "templates/storage/s3-buckets.yaml:templates/storage/s3-buckets.yaml"
    "templates/frontend/cloudfront.yaml:templates/frontend/cloudfront.yaml"
    "templates/backend/database.yaml:templates/backend/database.yaml"
    "templates/backend/ecs.yaml:templates/backend/ecs.yaml"
    "templates/backend/api-gateway.yaml:templates/backend/api-gateway.yaml"
    "templates/iam/github-actions.yaml:templates/iam/github-actions.yaml"
)

# Upload each template
for template in "${TEMPLATES[@]}"; do
    # Split the template string into source and destination
    SOURCE=${template%%:*}
    DESTINATION=${template#*:}
    
    # Check if the source file exists
    if [[ -f "$SOURCE" ]]; then
        print_status "Uploading ${SOURCE} to s3://${BUCKET_NAME}/${DESTINATION}..."
        
        aws s3 cp $SOURCE s3://${BUCKET_NAME}/${DESTINATION} --region $REGION
    else
        print_warning "Template file not found: ${SOURCE}"
    fi
done

print_header "=== Template Upload Complete ==="
print_status "Templates uploaded to: s3://${BUCKET_NAME}/templates/"
print_status "Template URL for CloudFormation: https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/templates/main.yaml"

# Generate a pre-signed URL with 7 day expiration
PRESIGNED_URL=$(aws s3 presign s3://${BUCKET_NAME}/templates/main.yaml --expires-in 604800 --region $REGION)
print_status "Pre-signed URL (valid for 7 days): ${PRESIGNED_URL}"

print_header "Next Steps"
print_status "You can now use this template in the CloudFormation console or with AWS CLI:"
echo ""
echo "aws cloudformation create-stack \\"
echo "  --stack-name my-full-stack-app \\"
echo "  --template-url https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/templates/main.yaml \\"
echo "  --parameters ParameterKey=Environment,ParameterValue=dev ParameterKey=TemplatesBucket,ParameterValue=${BUCKET_NAME} \\"
echo "  --capabilities CAPABILITY_NAMED_IAM \\"
echo "  --region ${REGION}"
echo ""
print_status "Make sure to set the 'TemplatesBucket' parameter to: ${BUCKET_NAME}" 