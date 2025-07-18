#!/bin/bash

setup_gar_environment() {
  local project="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT:-}"
  local region="${BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION:-us}"

  if ! command_exists gcloud; then
    log_error "Google Cloud SDK is required for GAR provider"
    exit 1
  fi

  if [[ -z "$project" ]]; then
    log_error "GAR project is required"
    exit 1
  fi

  log_info "Using GAR project: $project"
  log_info "Using GAR region: $region"

  # Determine correct registry host based on region value.
  # If the region ends with ".pkg.dev" we assume Google Artifact Registry
  # (e.g. europe-west10-docker.pkg.dev). Otherwise we default to Container
  # Registry (e.g. eu.gar.io).
  local registry_host
  if [[ "${region}" =~ \.pkg\.dev$ ]]; then
    registry_host="${region}"
  else
    registry_host="${region}.gar.io"
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
  local cache_key="$1"
  local cache_image

  cache_image=$(build_cache_image_name "gar" "$cache_key")

  if image_exists_in_registry "$cache_image"; then
    log_info "Cache hit! Restoring from $cache_image"
    if pull_image "$cache_image"; then
      tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
      log_success "Cache restored successfully from GAR"
      return 0
    else
      log_warning "Failed to pull cache image from GAR"
      return 1
    fi
  else
    log_info "Cache miss. No cached image found for key $cache_key in GAR. Proceeding without cache."
    return 0
  fi
}

save_gar_cache() {
  local cache_key="$1"
  local cache_image
  local source_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  cache_image=$(build_cache_image_name "gar" "$cache_key")

  if ! image_exists_locally "$source_image"; then
    log_error "Source image not found locally: $source_image"
    return 1
  fi

  if tag_image "$source_image" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to GAR: $cache_image"
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
