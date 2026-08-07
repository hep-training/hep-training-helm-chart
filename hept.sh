#!/bin/bash

set -euo pipefail # stop when error occurs

# ======================== CONFIGURATION ========================
readonly HEP_TRAINING_PATH="/path/to/your/hep-training/repo"
readonly GITHUB_USERNAME="GITHUB_USERNAME"
readonly IMAGE_NAME="IMAGE_NAME"
readonly IMAGE_TAG="IMAGE_TAG"
readonly DOCKER_REGISTRY="ghcr.io"
readonly IMAGE_FULL="$DOCKER_REGISTRY/$GITHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

# ======================== COLORS ========================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# ======================== FUNCTIONS ========================

# error message
error() {
    echo -e "${RED} ERROR: $*${NC}" >&2
    exit 1
}

# success message
success() {
    echo -e "${GREEN} $*${NC}"
}

# info message
info() {
    echo -e "${YELLOW} $*${NC}"
}

usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    install                     Install the application
    upgrade                     Upgrade the application
    copy-ror-config, crc        Copy config files from HEP Training repository
    uninstall                   Uninstall the application

Options: 
    --help, -h                  Show this help message

Examples:
    $0 install
    $0 upgrade
    $0 crc
    $0 uninstall
EOF
}


check_prerequisites() {
    info "Vérification des prérequis..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not installed. Please install Docker."
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not installed. Please install kubectl."
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        error "Helm not installed. Please install Helm."
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon not running."
    fi

    # Check Kubernetes connection
    #if ! kubectl cluster-info &> /dev/null; then
    #    error "Cannot connect to Kubernetes cluster."
    #fi

    # Check HEP_TRAINING_PATH var
    if [ ! -d "$HEP_TRAINING_PATH" ]; then
        error "$HEP_TRAINING_PATH not found"
    fi

    # Check les fichiers source
    if [ ! -f "$HEP_TRAINING_PATH/config/tess.yml" ]; then
        error "file not found: $HEP_TRAINING_PATH/config/tess.yml"
    fi
    if [ ! -f "$HEP_TRAINING_PATH/config/secrets.yml" ]; then
        error "file not found: $HEP_TRAINING_PATH/config/secrets.yml"
    fi
    if [ ! -f "$HEP_TRAINING_PATH/.env" ]; then
        error "file not found: $HEP_TRAINING_PATH/.env"
    fi

    # Check le Dockerfile
    if [ ! -f "$HEP_TRAINING_PATH/Dockerfile" ]; then
        error "Dockerfile not found int $HEP_TRAINING_PATH"
    fi

    success "Checks are OK."
}

# Copies configuration files
copy_config() {
    info "Copying HEP Training configuration files..."

    # Copy config files
    if ! cp "$HEP_TRAINING_PATH/config/tess.yml" templates/config/tess.yml 2>/dev/null; then
        error "Failed to copy tess.yml"
    fi

    if ! cp "$HEP_TRAINING_PATH/config/secrets.yml" templates/config/secrets.yml 2>/dev/null; then
        error "Failed to copy secrets.yml"
    fi

    if ! cp "$HEP_TRAINING_PATH/.env" templates/config/.env 2>/dev/null; then
        error "Failed to copy .env"
    fi

    success "Configuration files copied."
}

create_kubernetes_secrets() {

    info "Creating Kubernetes secrets..."

    if ! kubectl create secret generic app-secrets-env \
        --from-env-file=templates/config/.env \
        --dry-run=client -o yaml > templates/app-secrets-env.yaml 2>/dev/null; then
        error "Failed to create app-secrets-env"
    fi

    if ! kubectl create secret generic app-secrets-config \
        --from-file=templates/config/secrets.yml \
        --from-file=templates/config/tess.yml \
        --dry-run=client -o yaml > templates/app-secrets-config.yaml 2>/dev/null; then
        error "Failed to create app-secrets-config"
    fi

    success "Kubernetes secrets created."
}

# Builds and pushes the Docker image
build_and_push_docker() {
    info "Building and pushing Docker image..."

    local original_dir
    original_dir=$(pwd)

    cd "$HEP_TRAINING_PATH" || error "Failed to access $HEP_TRAINING_PATH"

    # Build the image
    if ! docker build \
        -f Dockerfile . \
        --build-arg CR="True" \
        -t "$IMAGE_FULL" \
        --platform linux/amd64 2>&1 | grep -v "^$"; then
        error "Error while building Docker image"
    fi

    success "Docker image built: $IMAGE_FULL"

    # Check for sensitive files
    info "Checking for sensitive files..."

    local sensitive_count
    sensitive_count=$(docker run --rm "$IMAGE_FULL" \
        find -L . \( -path "*tess*" -o -path "*secrets*" -o -path "*env*" \) \
        -type f 2>/dev/null | grep -E "(\.env|tess\.yml|secrets\.yml)$" | wc -l)

    if [ "$sensitive_count" -gt 2 ]; then
        error "Sensitive files detected in Docker image ($sensitive_count files). Please check the Dockerfile."
    fi

    success "No sensitive files detected."

    # Push the image
    info "Pushing image to $DOCKER_REGISTRY..."
    if ! docker push "$IMAGE_FULL" 2>&1 | grep -v "^$"; then
        error "Error while pushing Docker image"
    fi

    success "Docker image pushed successfully."

    cd "$original_dir" || error "Failed to return to original directory"
}

# Verifies the values.yaml file
check_values_file() {

    if [ ! -f "./values.yaml" ]; then
        error "File 'values.yaml' not found. Stopping program."
    fi

    success "File 'values.yaml' found."
}

# Installs the application
install_app() {

    sed -i "s/EXEC_TYPE/rake db:setup/g" templates/app-setup-job.yaml

    info "Starting installation..."

    check_values_file
    check_prerequisites
    create_kubernetes_secrets

    build_and_push_docker

    info "Running Helm installation..."
    if ! helm install tess . -f values.yaml; then
        error "Error during Helm installation"
    fi

    sed -i "s/rake db:setup/EXEC_TYPE/g" templates/app-setup-job.yaml

    success "Application installed successfully!"
}

# Upgrades the application
upgrade_app() {

    sed -i "s/EXEC_TYPE/rails db:migrate/g" templates/app-setup-job.yaml

    info "Starting upgrade..."

    check_values_file
    check_prerequisites
    create_kubernetes_secrets

    info "Running Helm upgrade..."
    if ! helm upgrade tess . -f values.yaml; then
        error "Error during Helm upgrade"
    fi

    sed -i "s/rails db:migrate/EXEC_TYPE/g" templates/app-setup-job.yaml

    success "Application upgraded successfully!"
}

uninstall_app() {
    info "Stopping application..."
    if ! helm uninstall tess; then
        error "Error during Helm upgrade"
    fi
    success "Application stopped successfully!"
}

# ======================== MAIN ========================

main() {
    # Check that at least one command is provided
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    local command="$1"

    # Execute the appropriate command
    case "$command" in
        install)
            install_app
            ;;
        upgrade)
            upgrade_app
            ;;
        copy-ror-config|crc)
            copy_config
            ;;
        uninstall)
            uninstall_app
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

main "$@"
