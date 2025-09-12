#!/bin/bash

setup_artifactory_environment() {
  local registry_url_raw="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL:-}"
  local username_raw="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME:-}"
  local identity_token_raw="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN:-}"

  # Validate required parameters
  if [[ -z "$registry_url_raw" ]]; then
    log_error "Artifactory registry URL is required"
    log_info "Set it via the 'registry-url' parameter in artifactory configuration"
    exit 1
  fi

  if [[ -z "$username_raw" ]]; then
    log_error "Artifactory username is required"
    log_info "Set it via the 'username' parameter in artifactory configuration"
    exit 1
  fi

  if [[ -z "$identity_token_raw" ]]; then
    log_error "Artifactory identity token is required"
    log_info "Set it via the 'identity-token' parameter in artifactory configuration"
    exit 1
  fi

  # Process environment variable references in parameters
  local registry_url
  registry_url=$(expand_env_var "$registry_url_raw" "registry-url")

  local username
  username=$(expand_env_var "$username_raw" "username")

  local identity_token
  identity_token=$(expand_env_var "$identity_token_raw" "identity-token")

  # Clean up registry URL (remove protocol if present)
  registry_url="${registry_url#https://}"
  registry_url="${registry_url#http://}"

  # Validate expanded registry URL format
  if [[ ! "$registry_url" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] || [[ ${#registry_url} -lt 3 ]] || [[ ${#registry_url} -gt 253 ]]; then
    log_error "invalid Artifactory registry URL '$registry_url' - must be a valid hostname"
    exit 1
  fi

  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL="$registry_url"

  log_info "Artifactory registry URL: $registry_url"
  log_info "Artifactory username: $username"

  log_info "Authenticating with Artifactory Docker registry..."
  if docker login "$registry_url" -u "$username" -p "$identity_token"; then
    log_success "Successfully authenticated with Artifactory"
  else
    log_error "Failed to authenticate with Artifactory"
    log_info "Verify your username and identity token are correct"
    log_info "Ensure the registry URL is accessible and supports Docker registry API"
    exit 1
  fi
}

restore_artifactory_cache() {
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
          log_success "Cache restored successfully from Artifactory"
          return 0
        else
          log_warning "Failed to pull cache image from Artifactory"
          return 1
        fi
      else
        log_info "Cache miss. No cached image found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in Artifactory."
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
        log_info "No build cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in Artifactory."
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
          log_success "Cache restored successfully from Artifactory - build can be skipped"
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
        local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
        local fallback_cache_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"
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

save_artifactory_cache() {
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

  # Build cache image name with latest tag for layer caching
  local repository="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REPOSITORY:-${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}}"
  local latest_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL}/${repository}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:latest"

  if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to Artifactory: $cache_image"

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
      log_error "Failed to save cache to Artifactory"
      return 1
    fi
  else
    log_error "Failed to tag cache image for Artifactory"
    return 1
  fi
}