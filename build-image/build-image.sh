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

# Registry helper functions for push with login retry
infer_registry() {
  local image="$1"
  local first="${image%%/*}"
  if [[ "$image" == */* && ( "$first" == *.* || "$first" == *:* ) ]]; then
    printf '%s' "$first"
    return 0
  fi
  return 1
}

sed_in_place() {
  local expr="$1"
  local file="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$expr" "$file"
  else
    sed -i "$expr" "$file"
  fi
}

registry_login_flow() {
  local registry="$1"
  local target=""
  if [ -n "$registry" ]; then
    target=" $registry"
  fi

  echo "Choose a login method:"
  echo "1) docker login${target}"
  echo "2) docker logout${target} && docker login${target} (switch account)"
  echo "3) Login with username + token (uses --password-stdin)"
  read -r -p "Your choice (1-3) [1]: " login_method
  login_method="${login_method:-1}"

  case "$login_method" in
    1)
      if [ -n "$registry" ]; then
        docker login "$registry"
      else
        docker login
      fi
      ;;
    2)
      if [ -n "$registry" ]; then
        docker logout "$registry" >/dev/null 2>&1 || true
        docker login "$registry"
      else
        docker logout >/dev/null 2>&1 || true
        docker login
      fi
      ;;
    3)
      read -r -p "Username: " login_user
      read -r -s -p "Token (will not echo): " login_token
      echo ""
      if [ -n "$registry" ]; then
        printf '%s' "$login_token" | docker login "$registry" -u "$login_user" --password-stdin
      else
        printf '%s' "$login_token" | docker login -u "$login_user" --password-stdin
      fi
      ;;
    *)
      echo "Invalid choice"
      return 1
      ;;
  esac
}

push_with_login_retry() {
  local image_ref="$1"
  local registry="$2"

  local push_output
  local push_status
  set +e
  push_output="$(docker push "$image_ref" 2>&1)"
  push_status=$?
  set -e

  if [ $push_status -eq 0 ]; then
    echo "$push_output"
    return 0
  fi

  echo "$push_output"
  echo "❌ Failed to push image: $image_ref"

  if echo "$push_output" | grep -qiE "insufficient_scope|unauthorized|authentication required|no basic auth credentials|requested access to the resource is denied"; then
    echo ""
    if [ -n "$registry" ]; then
      echo "🔐 Docker registry login required for: $registry"
    else
      echo "🔐 Docker registry login required"
    fi
    echo ""
    registry_login_flow "$registry" || return 1

    echo ""
    echo "🔁 Retrying push: $image_ref"

    local retry_output
    local retry_status
    set +e
    retry_output="$(docker push "$image_ref" 2>&1)"
    retry_status=$?
    set -e

    echo "$retry_output"
    if [ $retry_status -eq 0 ]; then
      return 0
    fi

    if echo "$retry_output" | grep -qiE "insufficient_scope|unauthorized|authentication required|no basic auth credentials|requested access to the resource is denied"; then
      echo ""
      echo "⚠ Push still failing after login."
      echo "   Ensure the token/user has permission to push to this registry."
    fi
    return 1
  fi

  echo "   Please run 'docker login' for your registry and re-run the script."
  return 1
}

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

    do_push="${SKIP_PUSH:-}"
    if [ -z "$do_push" ]; then
        read -r -p "Push to registry? (Y/n): " do_push
    fi

    if [[ ! "$do_push" =~ ^[Nn]$ ]] && [[ ! "$do_push" =~ ^(1|true|yes|y|on)$ ]]; then
        # default is yes on empty input
        do_push="y"
    fi

    if [[ "$do_push" =~ ^[Nn]$ ]]; then
        echo ""
        echo "ℹ️  Skipping push. Image is available locally as: $FULL_IMAGE"
    else
        echo ""
        echo "📤 Pushing to registry..."
        registry="$(infer_registry "$IMAGE_NAME" || true)"
        push_with_login_retry "$FULL_IMAGE" "$registry" || exit 1
        echo "✅ Image pushed successfully"

        # Also tag and push as latest if version is not latest
        if [ "$IMAGE_VERSION" != "latest" ]; then
            echo ""
            echo "📤 Tagging and pushing ${IMAGE_NAME}:latest..."
            docker tag "$FULL_IMAGE" "${IMAGE_NAME}:latest"
            push_with_login_retry "${IMAGE_NAME}:latest" "$registry" || exit 1
            echo "✅ Also pushed as ${IMAGE_NAME}:latest"
        fi
    fi
    
    # Update .env with new version
    if [ -f .env ]; then
        if grep -q '^IMAGE_NAME=' .env; then
            sed_in_place "s|^IMAGE_NAME=.*|IMAGE_NAME=$IMAGE_NAME|" .env
        else
            echo "IMAGE_NAME=$IMAGE_NAME" >> .env
        fi
        
        if grep -q '^IMAGE_VERSION=' .env; then
            sed_in_place "s|^IMAGE_VERSION=.*|IMAGE_VERSION=$IMAGE_VERSION|" .env
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
