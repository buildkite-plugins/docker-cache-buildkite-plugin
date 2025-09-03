#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Set up basic valid configuration
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='ecr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='my-app'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='us-east-1'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='123456789012'

  # N.B: Simple function mocks work fine for environment validation tests
  # since we only need to prevent actual AWS/Docker calls, not simulate
  # complex command interactions like in pre-command functional tests.
  function aws() { return 0; }
  function docker() { return 0; }
  export -f aws docker
}

@test "Fails with invalid image name - uppercase letters" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='MyApp'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid image name'
  assert_output --partial 'only lowercase letters'
}

@test "Fails with invalid image name - special characters" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='my@app'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid image name'
}

@test "Fails with invalid image name - starts with separator" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='-my-app'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'cannot start/end with separators'
}

@test "Fails with invalid image name - consecutive separators" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE='my--app'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'consecutive separators'
}

@test "Accepts valid image names" {
  for image in "my-app" "my_app" "my.app" "namespace/my-app" "registry.com/namespace/my-app"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_IMAGE="$image"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Fails with invalid strategy" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY='invalid'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid strategy'
  assert_output --partial 'artifact, build, hybrid'
}

@test "Accepts valid strategies" {
  for strategy in "artifact" "build" "hybrid"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_STRATEGY="$strategy"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Fails with invalid AWS account ID - wrong length" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='12345'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid AWS account ID'
  assert_output --partial 'must be 12 digits'
}

@test "Fails with invalid AWS account ID - contains letters" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_ACCOUNT_ID='12345678901a'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid AWS account ID'
}

@test "Fails with invalid AWS region format" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION='invalid-region'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid AWS region'
  assert_output --partial 'us-east-1'
}

@test "Accepts valid AWS regions" {
  for region in "us-east-1" "us-west-2" "eu-west-1" "ap-southeast-2"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGION="$region"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Fails with invalid ECR registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL='invalid-url'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ECR registry URL'
}

@test "Accepts valid ECR registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ECR_REGISTRY_URL='123456789012.dkr.ecr.us-east-1.amazonaws.com'

  run "$PWD"/hooks/environment
  assert_success
}

@test "GAR provider requires project ID" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT

  # Mock gcloud
  function gcloud() { return 0; }
  export -f gcloud

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'Google Cloud project ID is required'
}

@test "Fails with invalid Google Cloud project ID" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT='Invalid-Project'

  function gcloud() { return 0; }
  export -f gcloud

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid Google Cloud project ID'
}

@test "Accepts valid Google Cloud project IDs" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'

  function gcloud() { return 0; }
  export -f gcloud

  for project in "my-project" "my-project-123" "project123"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT="$project"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Fails with invalid GAR region" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT='my-project'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION='invalid-region'

  function gcloud() { return 0; }
  export -f gcloud

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid GAR region'
}

@test "Accepts valid GAR regions" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='gar'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_PROJECT='my-project'

  function gcloud() { return 0; }
  export -f gcloud

  for region in "us" "europe" "asia" "us-central1-docker.pkg.dev"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_GAR_REGION="$region"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Buildkite provider requires organization slug" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_API_TOKEN='fake-token'  # Set token so we get to org slug validation
  unset BUILDKITE_ORGANIZATION_SLUG
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_ORG_SLUG

  # Mock buildkite-agent
  function buildkite-agent() { return 0; }
  export -f buildkite-agent

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'Buildkite organization slug is required'
}

@test "Buildkite provider fails with invalid auth method" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_AUTH_METHOD='invalid'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  export BUILDKITE_API_TOKEN='fake-token'

  function buildkite-agent() { return 0; }
  function docker() { return 0; }
  export -f buildkite-agent docker

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid authentication method'
  assert_output --partial 'api-token'
  assert_output --partial 'oidc'
}

@test "Buildkite provider requires API token for api-token auth" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_AUTH_METHOD='api-token'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  unset BUILDKITE_API_TOKEN
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_API_TOKEN

  function buildkite-agent() { return 0; }
  function docker() { return 0; }
  export -f buildkite-agent docker

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'API token is required for api-token authentication'
}

@test "Buildkite provider fails with invalid organization slug" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_ORG_SLUG='Invalid-Org'
  export BUILDKITE_API_TOKEN='fake-token'

  function buildkite-agent() { return 0; }
  function docker() { return 0; }
  export -f buildkite-agent docker

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid organization slug'
}

@test "Buildkite provider fails with invalid registry slug" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_REGISTRY_SLUG='Invalid-Registry'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  export BUILDKITE_API_TOKEN='fake-token'

  function buildkite-agent() { return 0; }
  function docker() { return 0; }
  export -f buildkite-agent docker

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid registry slug'
}

@test "Buildkite provider accepts valid organization and registry slugs" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'
  export BUILDKITE_API_TOKEN='fake-token'

  function buildkite-agent() { return 0; }
  function docker() { return 0; }
  export -f buildkite-agent docker

  for org_slug in "my-org" "my-org-123" "org123"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_ORG_SLUG="$org_slug"

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "Buildkite provider works with OIDC authentication" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='buildkite'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_BUILDKITE_AUTH_METHOD='oidc'
  export BUILDKITE_ORGANIZATION_SLUG='my-org'

  function buildkite-agent() {
    if [[ "$1" == "oidc" && "$2" == "request-token" ]]; then
      echo "fake-oidc-token"
      return 0
    fi
    return 0
  }
  function docker() { return 0; }
  export -f buildkite-agent docker

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Authentication method: oidc'
  assert_output --partial 'Successfully authenticated with Buildkite Packages using OIDC'
}

@test "generate_cache_key creates hash from Dockerfile" {
  # Load the plugin library for testing
  source "$PWD/lib/plugin.bash"

  export BUILDKITE_PLUGIN_DOCKER_CACHE_DOCKERFILE='tests/fixtures/Dockerfile'

  # Create a test Dockerfile
  mkdir -p tests/fixtures
  echo "FROM alpine:latest" > tests/fixtures/Dockerfile

  run generate_cache_key
  assert_success
  # Should be a 40-character SHA1 hash
  assert [ ${#output} -eq 40 ]

  # Clean up
  rm -rf tests/fixtures
}
