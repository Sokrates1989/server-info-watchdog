#!/bin/bash

# =============================================================================
# Build and push Docker image for Server Info Watchdog Web UI
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
IMAGE_NAME="${IMAGE_NAME:-sokrates1989/server-info-watchdog-web}"
CI_ENV_FILE="$PROJECT_ROOT/.ci.env"

# Load version from .ci.env if it exists
if [ -f "$CI_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CI_ENV_FILE"
fi

IMAGE_VERSION="${IMAGE_VERSION:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}Server Info Watchdog Web UI - Image Builder${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# Prompt for version
read -rp "Enter image version [${IMAGE_VERSION}]: " input_version
IMAGE_VERSION="${input_version:-$IMAGE_VERSION}"

echo ""
echo -e "Building: ${YELLOW}${IMAGE_NAME}:${IMAGE_VERSION}${NC}"
echo ""

# Build the image
cd "$PROJECT_ROOT"

docker build \
    -f Dockerfile_web \
    --build-arg IMAGE_TAG="$IMAGE_VERSION" \
    -t "${IMAGE_NAME}:${IMAGE_VERSION}" \
    -t "${IMAGE_NAME}:latest" \
    .

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""

# Ask about pushing
if [ "${SKIP_PUSH:-false}" = "true" ]; then
    echo -e "${YELLOW}Skipping push (SKIP_PUSH=true)${NC}"
    exit 0
fi

read -rp "Push image to registry? [y/N]: " push_confirm
if [[ "$push_confirm" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Pushing ${IMAGE_NAME}:${IMAGE_VERSION}..."
    
    # Push with retry on auth failure
    push_image() {
        if ! docker push "${IMAGE_NAME}:$1" 2>&1; then
            echo -e "${RED}Push failed. Attempting docker login...${NC}"
            docker login
            docker push "${IMAGE_NAME}:$1"
        fi
    }
    
    push_image "$IMAGE_VERSION"
    push_image "latest"
    
    echo ""
    echo -e "${GREEN}Push complete!${NC}"
fi

# Update .ci.env with new version
if [ -f "$CI_ENV_FILE" ]; then
    if grep -q "^IMAGE_VERSION=" "$CI_ENV_FILE"; then
        # macOS/BSD sed compatibility
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^IMAGE_VERSION=.*/IMAGE_VERSION=${IMAGE_VERSION}/" "$CI_ENV_FILE"
        else
            sed -i "s/^IMAGE_VERSION=.*/IMAGE_VERSION=${IMAGE_VERSION}/" "$CI_ENV_FILE"
        fi
    else
        echo "IMAGE_VERSION=${IMAGE_VERSION}" >> "$CI_ENV_FILE"
    fi
    echo -e "${GREEN}Updated .ci.env with IMAGE_VERSION=${IMAGE_VERSION}${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
