# CloudFormation Template for AWS Full-Stack Applications

A comprehensive, production-ready CloudFormation template for deploying full-stack applications on AWS, supporting both frontend hosting via S3/CloudFront and backend services using ECS, RDS, VPC, and API Gateway.

## Features

- **Modular Template Structure**: Organized, maintainable nested stacks for each component
- **Environment-Specific Deployments**: Separate dev, staging, and production environments
- **Multi-Environment Support**: Staging, Production, Storybook, and Electron downloads
- **CloudFront CDN**: Global content delivery with optimized caching policies
- **GitHub Actions Integration**: Automated IAM user and access keys for CI/CD
- **Custom Domain Support**: SSL certificates and custom domain configuration
- **Content Type Handling**: CloudFront functions for proper MIME types
- **Backend Services**:
  - **ECS**: Container-based microservices with Fargate
  - **RDS**: Managed relational database (MySQL)
  - **VPC**: Secure networking with public and private subnets
  - **API Gateway**: REST API with GraphQL and admin endpoints
- **Security Best Practices**: Proper IAM policies and security groups
- **Flexible Configuration**: Enable/disable components as needed
- **Easy Management**: Deployment, invalidation, and deletion scripts

## Quick Start

### Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```

2. **jq** for JSON parsing (recommended)
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

3. **Appropriate AWS permissions** to create:
   - S3 buckets and policies
   - CloudFront distributions
   - IAM users and policies
   - VPC and networking components
   - ECS clusters and services
   - RDS databases
   - API Gateway APIs

## Template Structure

The CloudFormation template is organized in a modular structure using nested stacks:

```
templates/
  ├── main.yaml                   # Main template that orchestrates all other templates
  ├── networking/
  │   ├── vpc.yaml                # VPC, subnets, gateways, route tables
  │   └── security-groups.yaml    # Security groups for ECS, RDS, ALB
  ├── storage/
  │   └── s3-buckets.yaml         # S3 buckets for frontend hosting
  ├── frontend/
  │   └── cloudfront.yaml         # CloudFront distributions
  ├── backend/
  │   ├── database.yaml           # RDS database
  │   ├── ecs.yaml                # ECS cluster, tasks, services, ALB
  │   └── api-gateway.yaml        # API Gateway
  └── iam/
      └── github-actions.yaml     # IAM resources for GitHub Actions
```

### Packaging Templates

Before deployment, the nested templates need to be packaged and uploaded to an S3 bucket:

```bash
# Create / update S3 bucket for templates
./scripts/package-templates.sh my-cfn-templates us-east-1
```

This script:
1. Creates a bucket if it doesn't exist
2. Uploads all template files with the correct structure
3. Provides the URL to use for CloudFormation deployment

### Environment Deployment

The project now uses environment-specific deployments for dev, staging, and production:

1. **Clone and setup**:
   ```bash
   git clone <your-repo>
   cd cloudformation-template
   chmod +x scripts/*.sh examples/*.sh
   ```

2. **Package templates**:
   ```bash
   ./scripts/package-templates.sh my-cfn-templates us-east-1
   ```

3. **Deploy a development environment**:
   ```bash
   ./scripts/deploy-env.sh dev my-project-dev my-cfn-templates
   ```

4. **Deploy a staging environment**:
   ```bash
   ./scripts/deploy-env.sh staging my-project-staging my-cfn-templates
   ```

5. **Deploy a production environment**:
   ```bash
   ./scripts/deploy-env.sh prod my-project-prod my-cfn-templates
   ```

## Environment Configuration

Each environment has its own configuration file in the `parameters/environment/` directory:

- `parameters/environment/dev.json` - Development environment with frontend only
- `parameters/environment/staging.json` - Staging environment with frontend and backend
- `parameters/environment/prod.json` - Production environment with frontend and backend

You can customize these files to adjust settings for each environment.

## Environment Management Scripts

### Deploying an Environment

```bash
./scripts/deploy-env.sh <environment> [project-name] [region] [templates-bucket]

# Examples:
./scripts/deploy-env.sh dev                                # Deploy dev environment
./scripts/deploy-env.sh staging my-app us-west-2           # Deploy staging environment
./scripts/deploy-env.sh prod my-app us-east-1 my-templates # Deploy production with templates bucket
```

### Invalidating CloudFront Cache

```bash
./scripts/invalidate-env.sh <environment> [project-name] [region] [paths]

# Examples:
./scripts/invalidate-env.sh dev                   # Invalidate dev environment cache
./scripts/invalidate-env.sh prod my-app           # Invalidate prod environment cache
./scripts/invalidate-env.sh staging "" "" "/images/*"  # Invalidate specific paths
```

### Deleting an Environment

```bash
./scripts/delete-env.sh <environment> [project-name] [region]

# Examples:
./scripts/delete-env.sh dev                      # Delete dev environment
./scripts/delete-env.sh staging my-app us-west-2 # Delete staging environment
```

## Usage Examples

### Package and Deploy Templates

```bash
# Package templates to S3 bucket
./scripts/package-templates.sh my-cfn-templates us-east-1

# Check the output for confirmation and template URLs
```

### Frontend-Only Development Environment

Deploy and use a frontend-only development environment:

```bash
# Deploy dev environment
./scripts/deploy-env.sh dev my-frontend-app us-east-1 my-cfn-templates

# Upload your files
aws s3 sync ./dist s3://my-frontend-app-dev-staging-123456789012-us-east-1 --delete

# Invalidate cache
./scripts/invalidate-env.sh dev my-frontend-app us-east-1
```

### Full-Stack Staging Environment

Deploy a staging environment with both frontend and backend:

```bash
# First, create necessary secrets for database credentials
aws secretsmanager create-secret \
  --name my-full-app-staging-db-credentials \
  --description "DB credentials for staging app" \
  --secret-string '{"username":"dbadmin","password":"YourSecurePassword123!"}'

# Create parameter for container image
aws ssm put-parameter \
  --name "/app/my-full-app-staging/container-image" \
  --type "String" \
  --value "nginx:latest"

# Deploy staging environment
./scripts/deploy-env.sh staging my-full-app us-east-1 my-cfn-templates

# Upload frontend files
aws s3 sync ./dist s3://my-full-app-staging-staging-123456789012-us-east-1 --delete

# Invalidate cache
./scripts/invalidate-env.sh staging my-full-app us-east-1
```

### Production Environment with Custom Domain

Deploy a production environment with a custom domain:

1. **Create a custom parameter file**:
   ```bash
   cp parameters/environment/prod.json parameters/environment/prod-custom.json
   ```

2. **Edit the custom domain settings**:
   ```json
   {
     "ParameterKey": "CustomDomainName",
     "ParameterValue": "example.com"
   },
   {
     "ParameterKey": "CertificateArn", 
     "ParameterValue": "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
   }
   ```

3. **Deploy using the custom file**:
   ```bash
   ./scripts/deploy-env.sh prod my-prod-app
   ```

## 🤖 GitHub Actions Integration

### Dynamic Environment Workflow

Create a single workflow that handles multiple environments based on branch or event:

```yaml
name: Deploy
on:
  push:
    branches:
      - main             # staging environment
      - 'develop'      # dev environment
    paths-ignore:
      - '**.md'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        type: choice
        required: true
        default: 'dev'
        options:
          - 'dev'
          - 'staging'
          - 'prod'
      project_name:
        description: 'Project name (optional)'
        required: false
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      AWS_REGION: us-east-1
      TEMPLATES_BUCKET: my-cfn-templates
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Determine environment
        id: env
        run: |
          # Check if this is a workflow_dispatch event
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            # Use the inputs from workflow_dispatch
            ENV_NAME="${{ github.event.inputs.environment }}"
            
            # Use custom project name if provided, otherwise construct default
            if [[ -n "${{ github.event.inputs.project_name }}" ]]; then
              PROJECT_NAME="${{ github.event.inputs.project_name }}"
            else
              PROJECT_NAME="my-app-${ENV_NAME}"
            fi
          else
            # Push event - determine environment from branch
            if [[ $GITHUB_REF == 'refs/heads/main' ]]; then
              ENV_NAME="staging"
              PROJECT_NAME="my-app-staging"
            elif [[ $GITHUB_REF == 'refs/heads/develop' ]]; then
              ENV_NAME="dev"
              PROJECT_NAME="my-app-dev"
            else
              ENV_NAME="dev"
              PROJECT_NAME="my-app-dev"
            fi
          fi
          
          echo "ENV_NAME=$ENV_NAME" >> $GITHUB_OUTPUT
          echo "PROJECT_NAME=$PROJECT_NAME" >> $GITHUB_OUTPUT
          echo "Deploying to $ENV_NAME environment with project name $PROJECT_NAME"
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Build
        run: npm run build
      
      - name: Deploy Infrastructure (if needed)
        run: |
          # Skip if infrastructure already exists - modify this check as needed
          if ! aws cloudformation describe-stacks --stack-name ${{ steps.env.outputs.PROJECT_NAME }} 2>/dev/null; then
            echo "Deploying infrastructure for ${{ steps.env.outputs.ENV_NAME }} environment"
            ./scripts/deploy-env.sh ${{ steps.env.outputs.ENV_NAME }} ${{ steps.env.outputs.PROJECT_NAME }} ${{ env.AWS_REGION }} ${{ env.TEMPLATES_BUCKET }}
          else
            echo "Stack already exists, skipping infrastructure deployment"
          fi
      
      - name: Deploy to S3
        run: |
          # Get bucket name from CloudFormation output
          STACK_NAME="${{ steps.env.outputs.PROJECT_NAME }}"
          STORAGE_STACK=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?LogicalResourceId=='StorageStack'].PhysicalResourceId" --output text)
          BUCKET_NAME=$(aws cloudformation describe-stack-resources --stack-name $STORAGE_STACK --query "StackResources[?LogicalResourceId=='StagingBucket'].PhysicalResourceId" --output text)
          
          echo "Deploying to bucket: $BUCKET_NAME"
          aws s3 sync ./dist s3://$BUCKET_NAME --delete
      
      - name: Invalidate CloudFront
        run: |
          # Run the invalidation script
          ./scripts/invalidate-env.sh ${{ steps.env.outputs.ENV_NAME }} ${{ steps.env.outputs.PROJECT_NAME }} ${{ env.AWS_REGION }}
```

### Secrets Configuration

Store these secrets in your GitHub repository:

- `AWS_ACCESS_KEY_ID`: Access key for your CI/CD user
- `AWS_SECRET_ACCESS_KEY`: Secret access key for your CI/CD user

You can retrieve these values from the CloudFormation stack outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name my-app-dev \
  --query "Stacks[0].Outputs[?OutputKey=='GitHubActionsAccessKeyId'].OutputValue" \
  --output text

aws cloudformation describe-stacks \
  --stack-name my-app-dev \
  --query "Stacks[0].Outputs[?OutputKey=='GitHubActionsSecretAccessKey'].OutputValue" \
  --output text
```

## Template Parameters

### General Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `ProjectName` | Project name for resource naming | varies | Lowercase, alphanumeric, hyphens |
| `Environment` | Environment name | `dev` | `dev`, `staging`, `prod` |
| `TemplatesBucket` | S3 bucket containing nested templates | `cloudformation-templates` | Valid bucket name |

### Frontend Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `EnableStagingEnvironment` | Enable staging resources | varies | `true`, `false` |
| `EnableProductionEnvironment` | Enable production resources | varies | `true`, `false` |
| `EnableStorybookEnvironment` | Enable storybook resources | varies | `true`, `false` |
| `EnableElectronDownloads` | Enable electron app downloads | varies | `true`, `false` |
| `EnableGitHubActions` | Create CI/CD IAM resources | `true` | `true`, `false` |
| `DefaultRootObject` | Default file served | `index.html` | Any filename |
| `ErrorDocument` | Error page for SPA routing | `index.html` | Any filename |
| `PriceClass` | CloudFront price class | varies | `PriceClass_100`, `PriceClass_200`, `PriceClass_All` |
| `CustomDomainName` | Custom domain (optional) | empty | Domain name |
| `CertificateArn` | SSL certificate ARN | empty | ACM certificate ARN |

### Backend Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `EnableBackendResources` | Enable backend resources | `false` | `true`, `false` |
| `VpcCIDR` | CIDR block for the VPC | `10.0.0.0/16` | Valid CIDR |
| `PublicSubnet1CIDR` | CIDR for Public Subnet 1 | `10.0.0.0/24` | Valid CIDR |
| `PublicSubnet2CIDR` | CIDR for Public Subnet 2 | `10.0.1.0/24` | Valid CIDR |
| `PrivateSubnet1CIDR` | CIDR for Private Subnet 1 | `10.0.2.0/24` | Valid CIDR |
| `PrivateSubnet2CIDR` | CIDR for Private Subnet 2 | `10.0.3.0/24` | Valid CIDR |
| `DBInstanceClass` | RDS instance type | varies | Valid RDS instance |
| `DBName` | Database name | `appdb` | Alphanumeric |
| `DBUsername` | Database username | `dbadmin` | Alphanumeric |
| `DBPassword` | Database password | empty | SecureString |
| `ContainerImage` | ECS container image | empty | Valid image URI |
| `ContainerPort` | Container port | `3000` | Valid port |
| `DesiredCount` | Desired ECS tasks | varies | Number |

## Architecture

### Modular Nested Stacks

The template is organized as a main CloudFormation template that references nested stacks:

1. **Main Template**: Orchestrates and passes parameters to all nested stacks
2. **Networking Stacks**: VPC and security group templates
3. **Storage Stacks**: S3 bucket templates for frontend hosting
4. **Frontend Stacks**: CloudFront distributions and functions
5. **Backend Stacks**: Database, ECS, and API Gateway templates
6. **IAM Stacks**: GitHub Actions and permissions templates

This modular approach provides:
- Better organization and maintainability
- Ability to reuse components across projects
- Easier debugging when deployment issues occur
- Separation of concerns for different infrastructure components

### Environment Separation

Each environment is deployed as its own CloudFormation stack with:
- Unique resource names based on project name and environment
- Separate parameter configurations
- Independent lifecycle management
- Environment-specific secrets and parameters

### Resources Created

#### Frontend Resources

**S3 Buckets** (conditional based on configuration):
- `${ProjectName}-${Environment}-staging-${AccountId}-${Region}` - Staging website
- `${ProjectName}-${Environment}-prod-${AccountId}-${Region}` - Production website  
- `${ProjectName}-${Environment}-storybook-${AccountId}-${Region}` - Component documentation

**CloudFront Distributions**:
- Staging: Caching disabled for development
- Production: Optimized caching for performance
- Storybook: Caching disabled for frequent updates

#### Backend Resources

**VPC**:
- VPC with CIDR block
- 2 Public subnets (in different AZs)
- 2 Private subnets (in different AZs)
- Internet Gateway
- NAT Gateways (for private subnet internet access)
- Route tables and associations

**RDS Database**:
- MySQL database in private subnet
- Multi-AZ deployment
- Security group with access from ECS only

**ECS**:
- Fargate cluster
- Task definition with container configuration
- Service with load balancing
- CloudWatch logs for container output

**API Gateway**:
- REST API with regional endpoint
- GraphQL endpoint (/api/graphql)
- Admin dashboard endpoint (/admin/ui)
- CORS configuration for cross-origin requests

**IAM Resources**:
- GitHub Actions user with deployment permissions
- Policies for S3 and CloudFront access
- Access keys for CI/CD integration
- ECS task execution and task roles

**CloudFront Functions**:
- Content-Type header handling for `.cjs` and `.mjs` files
- CORS headers for cross-origin requests

### Security Features

- **VPC Segmentation**: Public/private subnet isolation
- **Security Groups**: Least privilege access controls
- **RDS Protection**: Database in private subnet
- **HTTPS Enforcement**: CloudFront and API Gateway redirect HTTP to HTTPS
- **IAM Permissions**: Minimal permissions for each role
- **Versioning**: S3 buckets have versioning enabled
- **Secrets Management**: Database credentials in Secrets Manager

### Cost Optimization

- **Environment Isolation**: Pay only for resources in deployed environments
- **Price Classes**: Configurable CloudFront pricing tiers
- **Caching Strategies**: Different caching for different environments
- **Fargate Spot**: Option for cost-effective ECS tasks
- **Multi-AZ Option**: Configurable high availability
- **Resource Sizing**: Appropriately sized database instances

## Monitoring and Troubleshooting

### Stack Status

```bash
# Check stack status for a specific environment
aws cloudformation describe-stacks \
  --stack-name my-app-staging \
  --region us-east-1

# View stack events
aws cloudformation describe-stack-events \
  --stack-name my-app-prod \
  --region us-east-1
```

### Container Logs

```bash
# Find the log group
aws logs describe-log-groups \
  --log-group-name-prefix "/ecs/my-app-staging"

# Get log streams
aws logs describe-log-streams \
  --log-group-name "/ecs/my-app-staging"

# View logs
aws logs get-log-events \
  --log-group-name "/ecs/my-app-staging" \
  --log-stream-name "ecs/my-app-staging-container/abcdef12345"
```

### Database Connection

```bash
# Get the database endpoint
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name my-app-prod \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
  --output text)

# Connect (requires psql client and network access)
psql -h $DB_ENDPOINT -U dbadmin -d appdb
```

### Common Issues

1. **Resource Limits**: Check service quotas if deployments fail
   - Solution: Request quota increases if needed

2. **Network Connectivity**: ECS tasks can't reach RDS
   - Solution: Check security groups and route tables

3. **Deployment Times**: Full stack can take 25-30 minutes to deploy
   - Expected: RDS and CloudFront are particularly slow to provision

4. **API Gateway Integration**: Errors with backend integration
   - Solution: Check ALB health checks and container port configuration

## Customization

### Backend Scaling

Modify the ECS service for higher capacity:

```json
{
  "ParameterKey": "DesiredCount",
  "ParameterValue": "4"
}
```

### Database Engine

Change to a different database engine:

```yaml
Database:
  Type: AWS::RDS::DBInstance
  Properties:
    Engine: mysql
    EngineVersion: 8.0.43
```

### API Gateway Authentication

Add Cognito or Lambda authorizers:

```yaml
ApiGatewayAdminMethod:
  Properties:
    AuthorizationType: COGNITO_USER_POOLS
    AuthorizerId: !Ref ApiGatewayAuthorizer
```

### Container Environment Variables

Add environment variables to the container:

```yaml
ContainerDefinitions:
  - Name: !Sub "${ProjectName}-container"
    Environment:
      - Name: DATABASE_URL
        Value: !Sub "mysql://${DBUsername}:${DBPassword}@${Database.Endpoint.Address}:${Database.Endpoint.Port}/${DBName}"
```