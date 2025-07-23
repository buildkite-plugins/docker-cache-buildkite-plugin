#!/bin/bash

# AWS ECR provider for Docker cache plugin

setup_ecr_environment() {
  if ! command_exists aws; then
    log_error "AWS CLI is required for ECR provider"
    exit 1
  fi

  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION:-}" ]]; then
    local region
    region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    log_info "Using AWS region: $region"
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION="$region"
  fi

  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID:-}" ]]; then
    log_info "Auto-detecting AWS account ID..."
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
      log_error "Failed to auto-detect AWS account ID. Please provide it in the configuration."
      exit 1
    fi
    log_info "Using AWS account ID: $account_id"
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID="$account_id"
  fi

  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL:-}" ]]; then
    local registry_url="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID}.dkr.ecr.${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}.amazonaws.com"
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL="$registry_url"
  fi

  log_info "ECR registry URL: ${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}"

  log_info "Authenticating with ECR..."
  if aws ecr get-login-password --region "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}" | docker login --username AWS --password-stdin "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}"; then
    log_success "Successfully authenticated with ECR"
  else
    log_error "Failed to authenticate with ECR"
    exit 1
  fi
}

restore_ecr_cache() {
  local cache_image

  cache_image=$(build_cache_image_name)

  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY:-hybrid}" in
    "artifact")
      # Artifact caching - restore complete image or nothing
      if image_exists_in_registry "$cache_image"; then
        log_info "Complete cache hit! Restoring from $cache_image"
        if pull_image "$cache_image"; then
          tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
          export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="true"
          log_success "Cache restored successfully from ECR"
          return 0
        else
          log_warning "Failed to pull cache image from ECR"
          return 1
        fi
      else
        log_info "Cache miss. No cached image found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in ECR."
        export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="false"
        return 0
      fi
      ;;
    "build")
      # Build caching - set up cache-from only
      if image_exists_in_registry "$cache_image"; then
        log_info "Build cache available: $cache_image"
        export BUILDKITE_PLUGIN_DOCKER_CACHE_FROM="$cache_image"
        export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="false"
      else
        log_info "No build cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in ECR."
        export BUILDKITE_PLUGIN_DOCKER_CACHE_FROM=""
        export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="false"
      fi
      return 0
      ;;
    "hybrid"|*)
      # Hybrid approach - try complete cache hit first, fall back to build caching
      if image_exists_in_registry "$cache_image"; then
        log_info "Complete cache hit! Restoring from $cache_image"
        if pull_image "$cache_image"; then
          tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
          export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="true"
          log_success "Cache restored successfully from ECR - build can be skipped"
          return 0
        else
          log_warning "Failed to pull complete cache image, falling back to build caching"
          export BUILDKITE_PLUGIN_DOCKER_CACHE_FROM="$cache_image"
          export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="false"
          return 0
        fi
      else
        log_info "No cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} - will build from scratch"
        # Try to find any existing cache image for layer caching by checking for latest tag
        local fallback_cache_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"
        if image_exists_in_registry "$fallback_cache_image"; then
          log_info "Using latest cache for layer caching: $fallback_cache_image"
          export BUILDKITE_PLUGIN_DOCKER_CACHE_FROM="$fallback_cache_image"
        else
          export BUILDKITE_PLUGIN_DOCKER_CACHE_FROM=""
          log_warning "No fallback cache found for layer caching"
        fi
        export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="false"
        return 0
      fi
      ;;
  esac
}

save_ecr_cache() {
  local cache_image

  # Skip save if we had a complete cache hit (image wasn't rebuilt)
  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_HIT:-false}" == "true" ]]; then
    log_info "Cache was restored from complete image - no need to save"
    return 0
  fi

  cache_image=$(build_cache_image_name)

  if ! image_exists_locally "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"; then
    case "${BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY:-hybrid}" in
      "artifact")
        log_error "Source image not found locally: ${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
        return 1
        ;;
      "build"|"hybrid"|*)
        log_warning "Source image not found locally: ${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE} - this is expected if build was skipped or failed"
        return 0
        ;;
    esac
  fi

  log_info "Ensuring ECR repository exists: ${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  if ! aws ecr describe-repositories --repository-names "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" --region "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}" >/dev/null 2>&1; then
    log_info "Creating ECR repository: ${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
    if aws ecr create-repository --repository-name "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" --region "${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION}" >/dev/null; then
      log_success "ECR repository created successfully"
    else
      log_error "Failed to create ECR repository"
      return 1
    fi
  fi

  # Build cache image name with latest tag for layer caching
  local latest_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"

  if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to ECR: $cache_image"

      # Also tag and push as :latest for layer caching fallback
      if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$latest_image"; then
        if push_image "$latest_image"; then
          log_success "Latest tag saved for layer caching: $latest_image"
        else
          log_warning "Failed to push latest tag (cache still saved)"
        fi
      else
        log_warning "Failed to tag latest image (cache still saved)"
      fi

      return 0
    else
      log_error "Failed to save cache to ECR"
      return 1
    fi
  else
    log_error "Failed to tag cache image for ECR"
    return 1
  fi
}
