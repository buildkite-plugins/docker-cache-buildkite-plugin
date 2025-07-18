#!/bin/bash

setup_gcr_environment() {
  local project="${BUILDKITE_PLUGIN_DOCKER_CACHE_GCR_PROJECT:-}"
  local region="${BUILDKITE_PLUGIN_DOCKER_CACHE_GCR_REGION:-us}"

  if ! command_exists gcloud; then
    log_error "Google Cloud SDK is required for GCR provider"
    exit 1
  fi

  if [[ -z "$project" ]]; then
    log_error "GCR project is required"
    exit 1
  fi

  log_info "Using GCR project: $project"
  log_info "Using GCR region: $region"

  log_info "Authenticating with GCR..."
  if gcloud auth configure-docker "${region}.gcr.io" --quiet; then
    log_success "Successfully authenticated with GCR"
  else
    log_error "Failed to authenticate with GCR"
    exit 1
  fi
}

restore_gcr_cache() {
  local cache_key="$1"
  local cache_image

  cache_image=$(build_cache_image_name "gcr" "$cache_key")

  if image_exists_in_registry "$cache_image"; then
    log_info "Cache hit! Restoring from $cache_image"
    if pull_image "$cache_image"; then
      tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
      log_success "Cache restored successfully from GCR"
      return 0
    else
      log_warning "Failed to pull cache image from GCR"
      return 1
    fi
  else
    log_info "Cache miss. No cached image found for key $cache_key in GCR. Proceeding without cache."
    return 0
  fi
}

save_gcr_cache() {
  local cache_key="$1"
  local cache_image
  local source_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  cache_image=$(build_cache_image_name "gcr" "$cache_key")

  if ! image_exists_locally "$source_image"; then
    log_error "Source image not found locally: $source_image"
    return 1
  fi

  if tag_image "$source_image" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to GCR: $cache_image"
      return 0
    else
      log_error "Failed to save cache to GCR"
      return 1
    fi
  else
    log_error "Failed to tag cache image for GCR"
    return 1
  fi
}
