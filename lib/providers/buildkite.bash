#!/bin/bash

setup_buildkite_environment() {
  local org_slug="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_ORG_SLUG:-}"
  local registry_slug="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_SLUG:-}"
  local auth_method="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_AUTH_METHOD:-api-token}"

  if ! command_exists buildkite-agent; then
    log_error "buildkite-agent is required for Buildkite provider"
    exit 1
  fi

  # Auto-detect organization slug from environment if not provided
  if [[ -z "$org_slug" ]]; then
    org_slug="${BUILDKITE_ORGANIZATION_SLUG:-}"
    if [[ -z "$org_slug" ]]; then
      log_error "Buildkite organization slug is required. Set it in configuration or BUILDKITE_ORGANIZATION_SLUG environment variable."
      exit 1
    fi
    log_info "Using organization slug from environment: $org_slug"
    export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_ORG_SLUG="$org_slug"
  fi

  # Default registry slug to image name if not provided
  if [[ -z "$registry_slug" ]]; then
    registry_slug="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
    log_info "Registry slug defaulting to image name: $registry_slug"
    export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_SLUG="$registry_slug"
  fi

  local registry_url="packages.buildkite.com/${org_slug}/${registry_slug}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_URL="$registry_url"

  log_info "Buildkite registry URL: $registry_url"
  log_info "Authentication method: $auth_method"

  # Authenticate with registry based on method
  case "$auth_method" in
    api-token)
      authenticate_with_api_token "$registry_url"
      ;;
    oidc)
      authenticate_with_oidc "$registry_url"
      ;;
    *)
      log_error "Unsupported authentication method: $auth_method"
      log_info "Supported methods: api-token, oidc"
      exit 1
      ;;
  esac
}

authenticate_with_api_token() {
  local registry_url="$1"
  local api_token_raw="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_API_TOKEN:-}"
  
  local api_token
  # Restrict environment variable expansion to safe, allow listed variables only
  # shellcheck disable=SC2016
  case "${api_token_raw}" in
    '$CONTAINER_PACKAGE_REGISTRY_TOKEN'|'$BUILDKITE_API_TOKEN'|'$BUILDKITE_PLUGIN_'*)
      local var_name="${api_token_raw#$}"
      api_token="${!var_name}"
      ;;
    *)
      api_token="${api_token_raw}"
      ;;
  esac

  # Fallback to environment variable for backward compatibility
  if [[ -z "$api_token" ]]; then
    api_token="${BUILDKITE_API_TOKEN:-}"
  fi

  if [[ -z "$api_token" ]]; then
    log_error "API token is required for api-token authentication"
    log_info "Set it via the 'api-token' parameter or BUILDKITE_API_TOKEN environment variable"
    log_info "Ensure your token has Read Packages and Write Packages scopes"
    exit 1
  fi

  log_info "Authenticating with Buildkite Packages using API token..."
  if docker login "$registry_url" -u buildkite -p "$api_token"; then
    log_success "Successfully authenticated with Buildkite Packages"
  else
    log_error "Failed to authenticate with Buildkite Packages"
    log_info "Verify your API token has Read Packages and Write Packages scopes"
    exit 1
  fi
}

authenticate_with_oidc() {
  local registry_url="$1"
  local audience="https://${registry_url}"
  
  log_info "Requesting OIDC token for audience: $audience"
  log_info "Authenticating with Buildkite Packages using OIDC..."

  if buildkite-agent oidc request-token --audience "$audience" --lifetime 300 | docker login "$registry_url" --username buildkite --password-stdin; then
    log_success "Successfully authenticated with Buildkite Packages using OIDC"
  else
    log_error "Failed to authenticate with Buildkite Packages using OIDC"
    log_info "Verify your pipeline has access to the registry and meets OIDC policy requirements"
    exit 1
  fi
}

restore_buildkite_cache() {
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
          log_success "Cache restored successfully from Buildkite Packages"
          return 0
        else
          log_warning "Failed to pull cache image from Buildkite Packages"
          return 1
        fi
      else
        log_info "Cache miss. No cached image found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in Buildkite Packages."
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
        log_info "No build cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in Buildkite Packages."
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
          log_success "Cache restored successfully from Buildkite Packages - build can be skipped"
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
        local fallback_cache_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${BUILDKITE_PLUGIN_DOCKER_CACHE_FALLBACK_TAG}"
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

save_buildkite_cache() {
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
  local latest_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_URL}/${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}:${BUILDKITE_PLUGIN_DOCKER_CACHE_FALLBACK_TAG}"

  if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to Buildkite Packages: $cache_image"

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
      log_error "Failed to save cache to Buildkite Packages"
      return 1
    fi
  else
    log_error "Failed to tag cache image for Buildkite Packages"
    return 1
  fi
}