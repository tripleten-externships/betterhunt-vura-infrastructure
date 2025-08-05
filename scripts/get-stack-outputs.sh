#!/bin/bash

# cloudformation stack outputs extractor
# extracts all outputs from a cloudformation stack and its nested stacks
# usage: ./get-stack-outputs.sh <stack-name> <region> [output-format]
# output formats: env, json, table, github-secrets

set -e

RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m'

print_header() {
    echo -e "${PURPLE}==================================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}==================================================================${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}----------------------------${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}----------------------------${NC}"
}

print_success() {
    echo ""
    echo -e "${GREEN}✓ $1${NC}"
    echo ""
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_dependencies() {
    local missing_deps=()
    
    if ! command_exists aws; then
        missing_deps+=("aws-cli")
    fi
    
    if ! command_exists jq; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install:"
        echo "  - AWS CLI: https://aws.amazon.com/cli/"
        echo "  - jq: https://stedolan.github.io/jq/"
        exit 1
    fi
}

get_stack_outputs() {
    local stack_name=$1
    local region=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]"
}

get_nested_stacks() {
    local parent_stack=$1
    local region=$2
    
    aws cloudformation list-stacks \
        --region "$region" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '$parent_stack') && StackName != '$parent_stack'].StackName" \
        --output json 2>/dev/null || echo "[]"
}

extract_output() {
    local outputs_json=$1
    local output_key=$2
    local default_value=${3:-"Not found"}
    
    local value=$(echo "$outputs_json" | jq -r --arg key "$output_key" '.[] | select(.OutputKey==$key) | .OutputValue // empty')
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

detect_database_type() {
    local port=$1
    case $port in
        "3306") echo "mysql" ;;
        "5432") echo "postgresql" ;;
        *) echo "mysql" ;; # default to mysql
    esac
}

generate_database_url() {
    local db_endpoint=$1
    local db_port=$2
    local db_name=$3
    local db_username=$4
    local db_password=$5
    local db_type=${6:-"mysql"}
    
    if [ "$db_endpoint" != "Not found" ] && [ "$db_name" != "Not found" ] && [ "$db_username" != "Not found" ]; then
        if [ -z "$db_password" ]; then
            # generate url without password - user can add password later
            echo "${db_type}://${db_username}:<PASSWORD>@${db_endpoint}:${db_port}/${db_name}"
        else
            echo "${db_type}://${db_username}:${db_password}@${db_endpoint}:${db_port}/${db_name}"
        fi
    else
        echo "Not found"
    fi
}

output_env_format() {
    local outputs_file=$1
    print_section "Environment Variables"
    while IFS='=' read -r key value; do
        echo -e "${ORANGE}${key}${NC}=${CYAN}${value}"
    done < "$outputs_file"
}

output_json_format() {
    local outputs_file=$1
    print_section "JSON Output"
    echo "{"
    local first=true
    while IFS='=' read -r key value; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo -n "  \"$key\": \"$value\""
    done < "$outputs_file"
    echo ""
    echo "}"
}

output_table_format() {
    local outputs_file=$1
    local descriptions_file=$2
    print_section "Table Output"
    printf "%-30s %-50s %s\n" "KEY" "VALUE" "DESCRIPTION"
    printf "%-30s %-50s %s\n" "---" "-----" "-----------"
    
    local temp_file=$(mktemp)
    while IFS='=' read -r key value; do
        local description=$(grep "^${key}=" "$descriptions_file" 2>/dev/null | cut -d'=' -f2- || echo "")
        printf "%-30s %-50s %s\n" "$key" "$value" "$description"
    done < "$outputs_file"
    rm -f "$temp_file"
}

output_github_secrets_format() {
    local outputs_file=$1
    echo ""
    print_section "GitHub Secrets Configuration"
    echo ""
    echo "Frontend Repository Secrets:"
    echo "============================"
    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^(GitHubActionsAccessKeyId|GitHubActionsSecretAccessKey|STAGING_|PRODUCTION_|STORYBOOK_|CloudFrontStack_StagingDistributionId|CloudFrontStack_ProductionDistributionId|CloudFrontStack_StorybookDistributionId|StorageStack_StagingBucketName|StorageStack_ProductionBucketName|StorageStack_StorybookBucketName|CloudFrontStack_ContentTypeFunctionArn) ]]; then
            echo -e "${ORANGE}${key}${NC}=${CYAN}${value}"
        fi
    done < "$outputs_file"
    echo -e "${NC}"
    echo "Backend Repository Secrets:"
    echo "==========================="
    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^(GitHubActionsAccessKeyId|GitHubActionsSecretAccessKey|ECR_REPOSITORY_NAME|EcsStack_EcsClusterName|EcsStack_EcsServiceName|DATABASE_URL|SHADOW_DATABASE_URL|DatabaseStack_DatabaseUsername|DatabaseStack_DatabaseEndpoint|DatabaseStack_DatabasePort|DatabaseStack_DatabaseName|ApiEndpoint|GraphqlEndpoint|AdminEndpoint|AWS_REGION|STACK_NAME) ]]; then
            echo -e "${ORANGE}${key}${NC}=${CYAN}${value}"
        fi
    done < "$outputs_file"
}

process_outputs() {
    local stack_name=$1
    local region=$2
    local format=$3
    
    print_header "Processing CloudFormation Stack: $stack_name in region: $region"
    
    local outputs_file=$(mktemp)
    local descriptions_file=$(mktemp)
    
    local main_outputs=$(get_stack_outputs "$stack_name" "$region")
    local nested_stacks=$(get_nested_stacks "$stack_name" "$region")
    
    if [ "$main_outputs" != "[]" ]; then
        print_section "Main Stack Outputs"
        
        local output_count=$(echo "$main_outputs" | jq length)
        for ((i=0; i<output_count; i++)); do
            local key=$(echo "$main_outputs" | jq -r ".[$i].OutputKey")
            local value=$(echo "$main_outputs" | jq -r ".[$i].OutputValue")
            local description=$(echo "$main_outputs" | jq -r ".[$i].Description // \"\"")
            
            echo "${key}=${value}" >> "$outputs_file"
            echo "${key}=${description}" >> "$descriptions_file"
            
            echo -e "${ORANGE}${key}${NC}=${CYAN}${value}${NC}"
        done
        echo ""
    fi
    
    local nested_count=$(echo "$nested_stacks" | jq length)
    if [ "$nested_count" -gt 0 ]; then
        print_section "Nested Stack Outputs"
        
        for ((i=0; i<nested_count; i++)); do
            local nested_stack=$(echo "$nested_stacks" | jq -r ".[$i]")
            local nested_outputs=$(get_stack_outputs "$nested_stack" "$region")
            
            if [ "$nested_outputs" != "[]" ]; then
                echo "Processing nested stack: $nested_stack"
                
                local nested_output_count=$(echo "$nested_outputs" | jq length)
                for ((j=0; j<nested_output_count; j++)); do
                    local key=$(echo "$nested_outputs" | jq -r ".[$j].OutputKey")
                    local value=$(echo "$nested_outputs" | jq -r ".[$j].OutputValue")
                    local description=$(echo "$nested_outputs" | jq -r ".[$j].Description // \"\"")
                    
                    local nested_prefix=$(echo "$nested_stack" | sed "s/${stack_name}-//" | sed 's/-[A-Z0-9]*$//')
                    local prefixed_key="${nested_prefix}_${key}"
                    
                    echo "${prefixed_key}=${value}" >> "$outputs_file"
                    echo "${prefixed_key}=${description}" >> "$descriptions_file"
                done
            fi
        done
    fi
    
    generate_derived_values "$outputs_file" "$descriptions_file" "$region" "$stack_name"

    case $format in
        "env")
            output_env_format "$outputs_file"
            ;;
        "json")
            output_json_format "$outputs_file"
            ;;
        "table")
            output_table_format "$outputs_file" "$descriptions_file"
            ;;
        "github-secrets")
            output_github_secrets_format "$outputs_file"
            ;;
        *)
            output_env_format "$outputs_file"
            ;;
    esac
    
    rm -f "$outputs_file" "$descriptions_file"
}

generate_derived_values() {
    local outputs_file=$1
    local descriptions_file=$2
    local region=$3
    local stack_name=$4
    
    local db_endpoint=$(grep "^DatabaseStack_DatabaseEndpoint=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^Database_DatabaseEndpoint=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^DatabaseEndpoint=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || echo "Not found")
    local db_port=$(grep "^DatabaseStack_DatabasePort=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^Database_DatabasePort=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^DatabasePort=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || echo "Not found")
    local db_name=$(grep "^DatabaseStack_DatabaseName=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^Database_DatabaseName=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^DatabaseName=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || echo "Not found")
    local db_username=$(grep "^DatabaseStack_DatabaseUsername=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^Database_DatabaseUsername=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || grep "^DatabaseUsername=" "$outputs_file" 2>/dev/null | cut -d'=' -f2- || echo "Not found")
    
    if [ "$db_endpoint" != "Not found" ] && [ "$db_port" != "Not found" ]; then
        local db_type=$(detect_database_type "$db_port")
        local db_url=$(generate_database_url "$db_endpoint" "$db_port" "$db_name" "$db_username" "" "$db_type")
        echo "DATABASE_URL=${db_url}" >> "$outputs_file"
        echo "DATABASE_URL=Generated database connection URL" >> "$descriptions_file"
        
        local shadow_db_url=$(generate_database_url "$db_endpoint" "$db_port" "${db_name}_shadow" "$db_username" "" "$db_type")
        echo "SHADOW_DATABASE_URL=${shadow_db_url}" >> "$outputs_file"
        echo "SHADOW_DATABASE_URL=Generated shadow database connection URL for Prisma" >> "$descriptions_file"
    fi
    
    local project_name=$(echo "$stack_name" | sed 's/-[^-]*$//')
    echo "ECR_REPOSITORY_NAME=${project_name}-backend" >> "$outputs_file"
    echo "ECR_REPOSITORY_NAME=Generated ECR repository name" >> "$descriptions_file"
    
    echo "AWS_REGION=${region}" >> "$outputs_file"
    echo "AWS_REGION=AWS region" >> "$descriptions_file"
    
    echo "STACK_NAME=${stack_name}" >> "$outputs_file"
    echo "STACK_NAME=CloudFormation stack name" >> "$descriptions_file"
}

show_usage() {
    echo "Usage: $0 <stack-name> <region> [output-format]"
    echo ""
    echo "Arguments:"
    echo "  stack-name     Name of the CloudFormation stack"
    echo "  region         AWS region (e.g., us-east-1)"
    echo "  output-format  Output format (optional, default: env)"
    echo ""
    echo "Output Formats:"
    echo "  env            Environment variables format (default)"
    echo "  json           JSON format"
    echo "  table          Table format with descriptions"
    echo "  github-secrets GitHub Actions secrets format"
    echo ""
    echo "Examples:"
    echo "  $0 my-app-dev us-east-1"
    echo "  $0 my-app-dev us-east-1 json"
    echo "  $0 my-app-dev us-east-1 github-secrets"
}

main() {
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        show_usage
        exit 1
    fi
    
    check_dependencies
    
    STACK_NAME=$1
    REGION=$2
    OUTPUT_FORMAT=${3:-"env"}
    
    case $OUTPUT_FORMAT in
        "env"|"json"|"table"|"github-secrets")
            ;;
        *)
            print_error "Invalid output format: $OUTPUT_FORMAT"
            show_usage
            exit 1
            ;;
    esac
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
        print_error "Stack '$STACK_NAME' not found in region '$REGION'"
        exit 1
    fi
    
    print_success "Stack found: $STACK_NAME"
    
    process_outputs "$STACK_NAME" "$REGION" "$OUTPUT_FORMAT"
    
    print_success "Output extraction completed!"
}

main "$@"