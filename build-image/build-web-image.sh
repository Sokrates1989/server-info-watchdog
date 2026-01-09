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
echo -e "${GREEN}Server Info Watchdog Web UI - Build & Push${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# Use environment variables if provided, otherwise prompt
if [ -n "$IMAGE_NAME" ]; then
    web_image_name="$IMAGE_NAME"
else
    # Prompt for image name
    read -rp "Docker image name [${IMAGE_NAME}]: " input_name
    web_image_name="${input_name:-$IMAGE_NAME}"
    
    if [ -z "$web_image_name" ]; then
        echo "❌ Image name is required"
        exit 1
    fi
fi

if [ -n "$IMAGE_VERSION" ]; then
    web_image_version="$IMAGE_VERSION"
else
    # Prompt for version
    read -rp "Enter image version [${IMAGE_VERSION}]: " input_version
    web_image_version="${input_version:-$IMAGE_VERSION}"
    
    if [ -z "$web_image_version" ]; then
        web_image_version="latest"
    fi
fi

IMAGE_NAME="$web_image_name"
IMAGE_VERSION="$web_image_version"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_VERSION}"
LATEST_IMAGE="${IMAGE_NAME}:latest"

echo ""
echo "📦 Will build and push:"
echo "   - $FULL_IMAGE"
echo "   - $LATEST_IMAGE"
echo ""
echo "🚀 Starting build and push process..."
echo ""

# Build the image with both tags
cd "$PROJECT_ROOT"

echo "📦 Building with tags: $FULL_IMAGE and $LATEST_IMAGE"
docker build \
    -f Dockerfile_web \
    --build-arg IMAGE_TAG="$IMAGE_VERSION" \
    -t "$FULL_IMAGE" \
    -t "$LATEST_IMAGE" \
    .

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""

# Auto-push both tags
echo "📤 Auto-pushing to registry..."

# Push with retry on auth failure
push_image() {
    local tag="$1"
    echo "📤 Pushing: ${IMAGE_NAME}:${tag}"
    if ! docker push "${IMAGE_NAME}:${tag}" 2>&1; then
        echo -e "${RED}Push failed. Attempting docker login...${NC}"
        docker login
        docker push "${IMAGE_NAME}:${tag}"
    fi
    echo "✅ Pushed: ${IMAGE_NAME}:${tag}"
}

push_image "$IMAGE_VERSION"
push_image "latest"

echo ""
echo -e "${GREEN}All images pushed successfully!${NC}"

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
