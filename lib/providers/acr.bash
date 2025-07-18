#!/bin/bash

setup_acr_environment() {
  local registry="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY:-}"
  local username="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_USERNAME:-}"
  local password="${BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_PASSWORD:-}"

  if [[ -z "$registry" ]]; then
    log_error "ACR registry is required (e.g. myregistry.azurecr.io)"
    exit 1
  fi

  log_info "Using Azure Container Registry: $registry"

  if [[ -n "$username" && -n "$password" ]]; then
    log_info "Authenticating with Azure Container Registry..."
    if echo "$password" | docker login "$registry" --username "$username" --password-stdin; then
      log_success "Successfully authenticated with Azure Container Registry"
    else
      log_error "Failed to authenticate with Azure Container Registry"
      exit 1
    fi
  else
    log_warning "No Azure credentials provided, assuming already authenticated or using public repository"
  fi
}

restore_acr_cache() {
  local cache_key="$1"
  local cache_image

  cache_image=$(build_cache_image_name "acr" "$cache_key")

  if image_exists_in_registry "$cache_image"; then
    log_info "Cache hit! Restoring from $cache_image"
    if pull_image "$cache_image"; then
      tag_image "$cache_image" "${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"
      log_success "Cache restored successfully from ACR"
      return 0
    else
      log_warning "Failed to pull cache image from ACR"
      return 1
    fi
  else
    log_info "Cache miss. No cached image found for key $cache_key in ACR. Proceeding without cache."
    return 0
  fi
}

save_acr_cache() {
  local cache_key="$1"
  local cache_image
  local source_image="${BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE}"

  cache_image=$(build_cache_image_name "acr" "$cache_key")

  if ! image_exists_locally "$source_image"; then
    log_error "Source image not found locally: $source_image"
    return 1
  fi

  if tag_image "$source_image" "$cache_image"; then
    if push_image "$cache_image"; then
      log_success "Cache saved successfully to ACR: $cache_image"
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
