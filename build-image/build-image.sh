#!/bin/bash
#
# build-image.sh
#
# Build and push the Server Info Watchdog Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Source git utilities for corruption detection
if [ -f "${PROJECT_ROOT}/setup/modules/git_utils.sh" ]; then
    source "${PROJECT_ROOT}/setup/modules/git_utils.sh"
    GIT_UTILS_LOADED=true
else
    GIT_UTILS_LOADED=false
fi

echo "🏗️  Server Info Watchdog - Build Production Image"
echo "=================================================="
echo ""

# Check for git corruption before building
if [ "$GIT_UTILS_LOADED" = true ]; then
    if detect_git_corruption; then
        echo "⚠️  Warning: Git repository corruption detected!"
        echo "   The build may show warnings about git commit information."
        echo ""
        check_and_offer_git_repair
        echo ""
    fi
fi

# Read current values from .env
if [ -f .env ]; then
    IMAGE_NAME=$(grep "^IMAGE_NAME=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "")
    IMAGE_VERSION=$(grep "^IMAGE_VERSION=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "")
fi

# Set defaults if not found
IMAGE_NAME="${IMAGE_NAME:-sokrates1989/server-info-watchdog}"
IMAGE_VERSION="${IMAGE_VERSION:-latest}"

# Prompt for image name
read -p "Docker image name [$IMAGE_NAME]: " input_name
IMAGE_NAME="${input_name:-$IMAGE_NAME}"

if [ -z "$IMAGE_NAME" ]; then
    echo "❌ Image name is required"
    exit 1
fi

# Prompt for version
read -p "Image version [$IMAGE_VERSION]: " input_version
IMAGE_VERSION="${input_version:-$IMAGE_VERSION}"

if [ -z "$IMAGE_VERSION" ]; then
    IMAGE_VERSION="latest"
fi

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_VERSION}"

echo ""
echo "📦 Building: $FULL_IMAGE"
echo ""

# Determine target platform (default to linux/amd64 for Swarm nodes)
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

echo "Target platform: $TARGET_PLATFORM"
echo ""

# Build the image, capturing output for git corruption detection
BUILD_EXIT_CODE=0
if docker buildx version >/dev/null 2>&1; then
    echo "📦 Using docker buildx for platform $TARGET_PLATFORM..."
    BUILD_OUTPUT=$(docker buildx build --platform "$TARGET_PLATFORM" -t "$FULL_IMAGE" --load . 2>&1) || BUILD_EXIT_CODE=$?
else
    echo "📦 docker buildx not found, falling back to docker build (host architecture)..."
    BUILD_OUTPUT=$(docker build -t "$FULL_IMAGE" . 2>&1) || BUILD_EXIT_CODE=$?
fi

echo "$BUILD_OUTPUT"

# Check for git corruption in build output
if [ "$GIT_UTILS_LOADED" = true ]; then
    if check_git_corruption_in_output "$BUILD_OUTPUT"; then
        echo ""
        echo "⚠️  Git corruption warnings detected during build."
        echo "   The image may have been built successfully, but git metadata is incomplete."
        handle_git_error_in_output "$BUILD_OUTPUT" "Docker build"
    fi
fi

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Image built successfully: $FULL_IMAGE"
    echo ""
    
    # Ask about pushing
    read -p "Push to registry? (y/N): " push_image
    if [[ "$push_image" =~ ^[Yy]$ ]]; then
        echo ""
        echo "📤 Pushing to registry..."
        docker push "$FULL_IMAGE"
        
        if [ $? -eq 0 ]; then
            echo "✅ Image pushed successfully"
            
            # Also tag and push as latest if version is not latest
            if [ "$IMAGE_VERSION" != "latest" ]; then
                read -p "Also push as 'latest'? (y/N): " push_latest
                if [[ "$push_latest" =~ ^[Yy]$ ]]; then
                    docker tag "$FULL_IMAGE" "${IMAGE_NAME}:latest"
                    docker push "${IMAGE_NAME}:latest"
                    echo "✅ Also pushed as ${IMAGE_NAME}:latest"
                fi
            fi
        else
            echo "❌ Failed to push image"
            exit 1
        fi
    fi
    
    # Update .env with new version
    if [ -f .env ]; then
        if grep -q '^IMAGE_NAME=' .env; then
            sed -i "s|^IMAGE_NAME=.*|IMAGE_NAME=$IMAGE_NAME|" .env
        else
            echo "IMAGE_NAME=$IMAGE_NAME" >> .env
        fi
        
        if grep -q '^IMAGE_VERSION=' .env; then
            sed -i "s|^IMAGE_VERSION=.*|IMAGE_VERSION=$IMAGE_VERSION|" .env
        else
            echo "IMAGE_VERSION=$IMAGE_VERSION" >> .env
        fi
        echo "✅ Updated .env with IMAGE_NAME=$IMAGE_NAME, IMAGE_VERSION=$IMAGE_VERSION"
    fi
else
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "🎉 Done!"
