#!/bin/bash

setup_gar_environment() {
  if ! command_exists gcloud; then
    log_error "Google Cloud SDK is required for GAR provider"
    exit 1
  fi

  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT:-}" ]]; then
    log_error "GAR project is required"
    exit 1
  fi

  log_info "Using GAR project: ${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}"
  log_info "Using GAR region: ${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}"

  # Determine correct registry host based on region value.
  # If the region ends with ".pkg.dev" we assume Google Artifact Registry
  # (e.g. europe-west10-docker.pkg.dev). Otherwise we default to Container
  # Registry (e.g. eu.gcr.io).
  local registry_host
  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" =~ \.pkg\.dev$ ]]; then
    registry_host="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}"
  else
    registry_host="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}.gcr.io"
  fi

  log_info "Authenticating with registry: ${registry_host}"
  if gcloud auth configure-docker "${registry_host}" --quiet; then
    log_success "Successfully authenticated with ${registry_host}"
  else
    log_error "Failed to authenticate with ${registry_host}"
    exit 1
  fi
}

restore_gar_cache() {
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
          log_success "Cache restored successfully from GAR"
          return 0
        else
          log_warning "Failed to pull cache image from GAR"
          return 1
        fi
      else
        log_info "Cache miss. No cached image found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in GAR."
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
        log_info "No build cache found for key ${BUILDKITE_PLUGIN_DOCKER_CACHE_KEY} in GAR."
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
          log_success "Cache restored successfully from GAR - build can be skipped"
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
        local fallback_cache_image
        fallback_cache_image=$(build_cache_image_name | sed 's/:cache-.*/:latest/')
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

save_gar_cache() {
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

  # Ensure GAR repository exists (Google Artifact Registry)
  # Only try to create repository if using Google Artifact Registry (.pkg.dev)
  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" =~ \.pkg\.dev$ ]] || [[ ! "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" =~ \.gcr\.io$ ]]; then
    log_info "Ensuring GAR repository exists: ${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-docker}"

    # Check if repository exists
    if ! gcloud artifacts repositories describe "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-docker}" --location="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" --project="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}" >/dev/null 2>&1; then
      log_info "Creating GAR repository: ${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-docker}"
      if gcloud artifacts repositories create "${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REPOSITORY:-docker}" --repository-format=docker --location="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}" --project="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT}" >/dev/null 2>&1; then
        log_success "GAR repository created successfully"
      else
        log_warning "Failed to create GAR repository - it may already exist or you may lack permissions"
      fi
    fi
  fi

  # Build latest image name for layer caching
  local latest_image
  latest_image=$(build_cache_image_name | sed 's/:cache-.*/:latest/')

  if tag_image "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to GAR: $cache_image"

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
      log_error "Failed to save cache to GAR"
      return 1
    fi
  else
    log_error "Failed to tag cache image for GAR"
    return 1
  fi
}
