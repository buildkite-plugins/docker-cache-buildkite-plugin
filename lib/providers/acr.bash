#!/bin/bash

# Azure Container Registry (ACR) provider for Docker cache plugin

setup_acr_environment() {
  if ! command_exists az; then
    log_error "Azure CLI (az) is required for ACR provider"
    log_info "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi

  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME:-}" ]]; then
    log_error "ACR registry name is required"
    log_info "Set it via the 'acr.registry-name' parameter"
    exit 1
  fi

  # Construct registry URL from registry name
  local registry_url="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME}.azurecr.io"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_URL="$registry_url"

  log_info "ACR registry URL: ${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_URL}"

  log_info "Authenticating with ACR..."
  if az acr login --name "${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME}" >/dev/null 2>&1; then
    log_success "Successfully authenticated with ACR"
  else
    log_error "Failed to authenticate with ACR"
    log_info "Ensure you have the required permissions (AcrPull, AcrPush) and are authenticated with Azure"
    exit 1
  fi
}

restore_acr_cache() {
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
          log_success "Cache restored successfully from ACR"
          return 0
        else
          log_warning "Failed to pull cache image from ACR"
          return 1
        fi
      else
        log_info "Cache miss. No cached image found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in ACR."
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
        log_info "No build cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in ACR."
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
          log_success "Cache restored successfully from ACR - build can be skipped"
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
        local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
        local fallback_cache_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"
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

save_acr_cache() {
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

  # Note: ACR automatically creates repositories on first push, no explicit creation needed
  log_info "Saving cache to ACR (repository will be auto-created if needed)"

  # Build cache image name with latest tag for layer caching
  local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
  local latest_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"

  if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to ACR: $cache_image"

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
      log_error "Failed to save cache to ACR"
      return 1
    fi
  else
    log_error "Failed to tag cache image for ACR"
    return 1
  fi
}
