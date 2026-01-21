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

@test "Artifactory provider requires registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'Artifactory registry URL is required'
  assert_output --partial "Set it via the 'artifactory.registry-url' parameter"
}

@test "Artifactory provider requires username" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'Artifactory username is required'
  assert_output --partial "Set it via the 'artifactory.username' parameter"
}

@test "Artifactory provider requires identity token" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  unset BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'Artifactory identity token is required'
  assert_output --partial "Set it via the 'artifactory.identity-token' parameter"
}

@test "Artifactory provider validates registry URL format" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='invalid@url'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid Artifactory registry URL'
  assert_output --partial 'must be a valid hostname'
}

@test "Artifactory provider strips https protocol from registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='https://test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'

  function docker() {
    if [[ "$1" == "login" && "$2" == "test.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success # Should succeed with mocked docker
  assert_output --partial 'Artifactory registry URL: test.jfrog.io'
}

@test "Artifactory provider strips http protocol from registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='http://test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'

  function docker() {
    if [[ "$1" == "login" && "$2" == "test.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success # Should succeed with mocked docker
  assert_output --partial 'Artifactory registry URL: test.jfrog.io'
}

@test "Artifactory provider validates repository name format" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REPOSITORY='Invalid@Repository'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid Artifactory repository name'
  assert_output --partial 'must contain only lowercase letters'
}

@test "Artifactory provider accepts valid configuration" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REPOSITORY='docker-repo'

  function docker() {
    if [[ "$1" == "login" && "$2" == "test.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Artifactory username: test@example.com'
  assert_output --partial 'Successfully authenticated with Artifactory'
}

@test "Artifactory provider processes environment variable token" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='$TEST_TOKEN'
  export TEST_TOKEN='actual-token-value'

  function docker() {
    if [[ "$1" == "login" && "$2" == "test.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Authenticating with Artifactory Docker registry'
}

@test "Artifactory provider fails when environment variable is empty" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='$EMPTY_TOKEN'
  unset EMPTY_TOKEN

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial "Environment variable 'EMPTY_TOKEN' referenced by identity-token parameter is empty or not set"
}

@test "Artifactory provider processes environment variable username" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='test.jfrog.io'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='$TEST_USERNAME'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  export TEST_USERNAME='test@example.com'

  function docker() {
    if [[ "$1" == "login" && "$2" == "test.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Artifactory username: test@example.com'
}

@test "Artifactory provider processes environment variable registry URL" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='artifactory'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_REGISTRY_URL='$TEST_REGISTRY'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_USERNAME='test@example.com'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ARTIFACTORY_IDENTITY_TOKEN='test-token'
  export TEST_REGISTRY='myregistry.jfrog.io'

  function docker() {
    if [[ "$1" == "login" && "$2" == "myregistry.jfrog.io" ]]; then
      return 0
    fi
    return 1
  }
  export -f docker

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Artifactory registry URL: myregistry.jfrog.io'
}

@test "expand_env_var function processes environment variable correctly" {
  # Load the plugin library for testing
  source "$PWD/lib/shared.bash"

  export TEST_VAR="test-value"
  result=$(expand_env_var '$TEST_VAR' "test-param")
  assert [ "$result" = "test-value" ]
}

@test "expand_env_var function returns literal values unchanged" {
  # Load the plugin library for testing
  source "$PWD/lib/shared.bash"

  result=$(expand_env_var "literal-value" "test-param")
  assert [ "$result" = "literal-value" ]
}

@test "expand_env_var function fails on undefined variable" {
  # Load the plugin library for testing
  source "$PWD/lib/shared.bash"

  unset UNDEFINED_VAR
  run expand_env_var '$UNDEFINED_VAR' "test-param"
  assert_failure
  assert_output --partial "Environment variable 'UNDEFINED_VAR' referenced by test-param parameter is empty or not set"
}

@test "expand_env_var function fails on empty variable" {
  # Load the plugin library for testing
  source "$PWD/lib/shared.bash"

  export EMPTY_VAR=""
  run expand_env_var '$EMPTY_VAR' "test-param"
  assert_failure
  assert_output --partial "Environment variable 'EMPTY_VAR' referenced by test-param parameter is empty or not set"
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

@test "ACR provider requires registry name" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'ACR registry name is required'
  assert_output --partial "Set it via the 'acr.registry-name' parameter"
}

@test "Fails with invalid ACR registry name - too short" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='abcd'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR registry name'
  assert_output --partial 'must be 5-50 alphanumeric characters'
}

@test "Fails with invalid ACR registry name - starts with number" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='123registry'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR registry name'
  assert_output --partial 'starting with a letter'
}

@test "Fails with invalid ACR registry name - contains hyphen" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='my-registry'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR registry name'
  assert_output --partial 'must be 5-50 alphanumeric characters'
}

@test "Accepts valid ACR registry names" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'

  # Test valid registry names
  for name in "myregistry" "Registry123" "testRegistry" "MyRegistry1234567890"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME="$name"

    function az() {
      if [[ "$1" == "acr" && "$2" == "login" ]]; then
        return 0
      fi
      return 1
    }
    export -f az

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "ACR provider validates repository name format" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='myregistry'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY='Invalid@Repository'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR repository name'
  assert_output --partial 'must contain only lowercase letters'
}

@test "ACR provider fails with repository starting with separator" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='myregistry'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY='/invalid-repo'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR repository name'
  assert_output --partial 'cannot start/end with separators'
}

@test "ACR provider fails with consecutive separators in repository" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='myregistry'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY='team//project'

  run "$PWD"/hooks/environment
  assert_failure
  assert_output --partial 'invalid ACR repository name'
  assert_output --partial 'cannot start/end with separators or have consecutive separators'
}

@test "ACR provider accepts valid repository names" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='myregistry'

  # Test valid repository names
  for repo in "docker-cache" "team/project" "team.project" "team_project" "my-app/cache"; do
    export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REPOSITORY="$repo"

    function az() {
      if [[ "$1" == "acr" && "$2" == "login" ]]; then
        return 0
      fi
      return 1
    }
    export -f az

    run "$PWD"/hooks/environment
    assert_success
  done
}

@test "ACR provider accepts valid configuration without repository" {
  export BUILDKITE_PLUGIN_DOCKER_CACHE_PROVIDER='acr'
  export BUILDKITE_PLUGIN_DOCKER_CACHE_ACR_REGISTRY_NAME='myregistry'

  function az() {
    if [[ "$1" == "acr" && "$2" == "login" ]]; then
      return 0
    fi
    return 1
  }
  export -f az

  run "$PWD"/hooks/environment
  assert_success
  assert_output --partial 'Setting up Docker cache environment'
}
