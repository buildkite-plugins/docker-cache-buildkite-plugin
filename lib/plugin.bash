#!/bin/bash

# Initialise default config values (exported env-vars)
plugin_read_config() {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_SAVE="${BUILDKITE_PLUGIN_DOCKER_CACHE_SAVE:-true}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_RESTORE="${BUILDKITE_PLUGIN_DOCKER_CACHE_RESTORE:-true}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_TAG="${BUILDKITE_PLUGIN_DOCKER_CACHE_TAG:-cache}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_VERBOSE="${BUILDKITE_PLUGIN_DOCKER_CACHE_VERBOSE:-false}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY="${BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY:-hybrid}"

  # Docker build related configuration
  export BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE="${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE:-Dockerfile}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_CONTEXT="${BUILDKITE_PLUGIN_DOCKER_CACHE_CONTEXT:-.}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_SKIP_PULL_FROM_CACHE="${BUILDKITE_PLUGIN_DOCKER_CACHE_SKIP_PULL_FROM_CACHE:-false}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_MAX_AGE_DAYS="${BUILDKITE_PLUGIN_DOCKER_CACHE_MAX_AGE_DAYS:-30}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_EXPORT_ENV_VARIABLE="${BUILDKITE_PLUGIN_DOCKER_CACHE_EXPORT_ENV_VARIABLE:-BUILDKITE_PLUGIN_DOCKER_IMAGE}"

  # Optional vars
  [[ -n "${BUILDKITE_PLUGIN_DOCKER_CACHE_TARGET:-}" ]] && export BUILDKITE_PLUGIN_DOCKER_CACHE_TARGET
  [[ -n "${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE_INLINE:-}" ]] && export BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE_INLINE
  [[ -n "${BUILDKITE_PLUGIN_DOCKER_CACHE_ADDITIONAL_BUILD_ARGS:-}" ]] && export BUILDKITE_PLUGIN_DOCKER_CACHE_ADDITIONAL_BUILD_ARGS

  # Export build args and secrets arrays
  for ((i=0; ; i++)); do
    local var_name="BUILDKITE_PLUGIN_DOCKER_CACHE_BUILD_ARGS_$i"
    if [[ -n "${!var_name:-}" ]]; then
      export "BUILDKITE_PLUGIN_DOCKER_CACHE_BUILD_ARGS_$i"
    else
      break
    fi
  done

  for ((i=0; ; i++)); do
    local var_name="BUILDKITE_PLUGIN_DOCKER_CACHE_SECRETS_$i"
    if [[ -n "${!var_name:-}" ]]; then
      export "BUILDKITE_PLUGIN_DOCKER_CACHE_SECRETS_$i"
    else
      break
    fi
  done
}

# Load shared utilities
# shellcheck source=lib/shared.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.bash"

# Export default configuration values so that later functions have them even
# when the user omits optional plugin keys (e.g. TAG)
plugin_read_config

# Load provider implementations
# shellcheck source=lib/providers/ecr.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/ecr.bash"
# shellcheck source=lib/providers/gar.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/gar.bash"
# shellcheck source=lib/providers/buildkite.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/buildkite.bash"
# shellcheck source=lib/providers/artifactory.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/artifactory.bash"
# shellcheck source=lib/providers/acr.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers/acr.bash"

if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_VERBOSE:-false}" == "true" ]]; then
  set -x
  PS4='[${BASH_SOURCE}:${LINENO}]: '
fi

setup_provider_environment() {
  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      setup_ecr_environment
      ;;
    gar)
      setup_gar_environment
      ;;
    buildkite)
      setup_buildkite_environment
      ;;
    artifactory)
      setup_artifactory_environment
      ;;
    acr)
      setup_acr_environment
      ;;
    *)
      unknown_provider "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}"
      ;;
  esac
}

generate_cache_key() {
  if [[ -n "${BUILDKITE_PLUGIN_DOCKER_CACHE_CACHE_KEY:-}" ]]; then
    # User provided explicit cache key
    if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_CACHE_KEY}" == *"/"* ]]; then
      # Treat as file path(s)
      echo "${BUILDKITE_PLUGIN_DOCKER_CACHE_CACHE_KEY}" | tr ',' '\n' | while read -r file; do
        if [[ -f "$file" ]]; then
          sha1sum "$file"
        else
          log_warning "Cache key file not found $file"
        fi
      done | sha1sum | cut -d' ' -f1
    else
      # Treat as string
      echo -n "${BUILDKITE_PLUGIN_DOCKER_CACHE_CACHE_KEY}" | sha1sum | cut -d' ' -f1
    fi
  else
    # Auto-generate cache key from common files
    local key_components=""

    if [[ -f "${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE}" ]]; then
      key_components="${key_components}$(sha1sum "${BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE}" | cut -d' ' -f1)"
    fi

    # Check for common dependency files
    for file in package.json yarn.lock requirements.txt Gemfile.lock composer.lock go.mod; do
      if [[ -f "$file" ]]; then
        key_components="${key_components}$(sha1sum "$file" | cut -d' ' -f1)"
      fi
    done

    # Include git commit if available
    if [[ -n "${BUILDKITE_COMMIT:-}" ]]; then
      key_components="${key_components}${BUILDKITE_COMMIT}"
    fi

    # Generate final key
    if [[ -n "$key_components" ]]; then
      echo -n "$key_components" | sha1sum | cut -d' ' -f1
    else
      # Fallback to timestamp-based key
      echo -n "$(date +%Y%m%d)" | sha1sum | cut -d' ' -f1
    fi
  fi
}

restore_cache() {
  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_RESTORE}" != "true" ]]; then
    log_info "Cache restore disabled, skipping"
    return 0
  fi

  log_info "Restoring cache from ${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER} using ${BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY} strategy"

  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      restore_ecr_cache
      ;;
    gar)
      restore_gar_cache
      ;;
    buildkite)
      restore_buildkite_cache
      ;;
    artifactory)
      restore_artifactory_cache
      ;;
    acr)
      restore_acr_cache
      ;;
    *)
      unknown_provider "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}"
      ;;
  esac

  export_cache_variables
}

save_cache() {
  if [[ "${BUILDKITE_PLUGIN_DOCKER_CACHE_SAVE}" != "true" ]]; then
    log_info "Cache save disabled, skipping"
    return 0
  fi

  log_info "Saving cache to ${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER} using ${BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY} strategy"

  case "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}" in
    ecr)
      save_ecr_cache
      ;;
    gar)
      save_gar_cache
      ;;
    buildkite)
      save_buildkite_cache
      ;;
    artifactory)
      save_artifactory_cache
      ;;
    acr)
      save_acr_cache
      ;;
    *)
      unknown_provider "${BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER}"
      ;;
  esac
}

export_cache_variables() {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_HIT="${BUILDKITE_PLUGIN_DOCKER_CACHE_HIT:-false}"
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE
}
