# Docker Cache Buildkite Plugin [![Build status](https://badge.buildkite.com/a3851ab6b8e918f7a29d1d43fd8a410308fd5a50455b8a4ab3.svg)](https://buildkite.com/buildkite/plugins-docker-cache)

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) for caching [Docker](https://docker.com) images across builds using various registry providers (ECR, GAR, ACR, Buildkite Packages, and Artifactory Docker Registry currently supported).

This plugin speeds up your Docker builds by caching images between pipeline runs. Instead of rebuilding the same Docker image every time, it stores built images in ECR, Google Artifact Registry, Azure Container Registry, Buildkite Packages, or Artifactory Docker Registry and reuses them when nothing has changed.

The plugin will check if a cached version of your image already exists. If it does, it pulls that instead of rebuilding. If not, it builds the image and saves it for next time. It automatically creates the necessary repositories in your registry if they don't exist (ECR, GAR, and ACR - Buildkite Packages registries are managed through the UI).

Cache keys are generated based on your Dockerfile content and build context, so the cache automatically invalidates when you make changes to your code or build configuration.

Also see the [Docker Buildkite Plugin](https://github.com/buildkite-plugins/docker-buildkite-plugin) for running pipeline steps in Docker containers.

## Example

### ECR Provider

The following pipeline will cache Docker builds in Amazon ECR.

```yaml
steps:
  - label: "🐳 Build with ECR cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### GAR Provider

The following pipeline will cache Docker builds in Google Artifact Registry:

```yaml
steps:
  - label: "🐳 Build with GAR cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: gar
          image: my-app
          gar:
            project: my-gcp-project
            region: us
```

### Buildkite Packages Provider

The following pipeline will cache Docker builds in Buildkite Packages Container Registry:

```yaml
steps:
  - label: "🐳 Build with Buildkite Packages cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: buildkite
          image: my-app
          buildkite:
            org-slug: my-org
```

#### With OIDC Authentication

```yaml
steps:
  - label: "🐳 Build with Buildkite Packages cache (OIDC)"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: buildkite
          image: my-app
          buildkite:
            org-slug: my-org
            auth-method: oidc
```

### Artifactory Docker Registry Provider

The following pipeline will cache Docker builds in Artifactory Docker Registry:

```yaml
steps:
  - label: "🐳 Build with Artifactory cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: artifactory
          image: my-app
          artifactory:
            registry-url: myjfroginstance.jfrog.io
            username: me@example.com
            identity-token: $ARTIFACTORY_IDENTITY_TOKEN
```

### Azure Container Registry (ACR) Provider

The following pipeline will cache Docker builds in Azure Container Registry:

```yaml
steps:
  - label: "🐳 Build with ACR cache"
    command: "echo 'Building with cache'"
    plugins:
      - docker-cache#v1.0.0:
          provider: acr
          image: my-app
          acr:
            registry-name: myregistry
```

### Cache Strategies

You can control how the cache is used with different strategies:

#### Artifact Strategy

Pulls the complete cached image if available, builds from scratch if not:

```yaml
steps:
  - label: "🐳 Artifact strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: artifact
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

#### Build Strategy

Uses layer caching during the build process:

```yaml
steps:
  - label: "🐳 Build strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: build
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

#### Hybrid Strategy

Tries artifact strategy first, falls back to build strategy if pull fails:

```yaml
steps:
  - label: "🐳 Hybrid strategy"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          strategy: hybrid
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### Multi-stage Builds

For multi-stage Dockerfiles, you can specify the target stage:

```yaml
steps:
  - label: "🐳 Multi-stage build"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          target: production
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

### Build Arguments

You can pass build arguments to Docker:

```yaml
steps:
  - label: "🐳 Build with args"
    plugins:
      - docker-cache#v1.0.0:
          provider: ecr
          image: my-app
          build-args:
            - NODE_ENV=production
            - API_URL=https://api.example.com
          ecr:
            region: us-east-1
            account-id: "123456789012"
```

## Configuration

These are all the options available to configure this plugin's behaviour.

### Required

#### `provider` (string)

Which registry provider to use for caching. Supported values: `ecr`, `gar`, `acr`, `buildkite`, `artifactory`.

#### `image` (string)

Name of your Docker image.

Example: `my-app`

### Optional

#### `strategy` (string, default: `hybrid`)

How to use the cache:

- `artifact`: Pull complete cached image if available, build from scratch if not
- `build`: Use layer caching during build process
- `hybrid`: Try artifact strategy first, fall back to build strategy if pull fails

#### `dockerfile` (string, default: `Dockerfile`)

Path to your Dockerfile.

#### `dockerfile-inline` (string)

Inline Dockerfile content instead of reading from a file.

#### `context` (string, default: `.`)

Docker build context path.

#### `target` (string)

Target stage for multi-stage builds.

#### `build-args` (array)

Build arguments to pass to Docker.

Example: `["NODE_ENV=production", "VERSION=1.0.0"]`

#### `additional-build-args` (string)

Additional docker build arguments as a single string.

Example: `"--network=host --build-arg CUSTOM_ARG=value"`

#### `secrets` (array)

Build secrets to pass to Docker (requires BuildKit).

Example: `["id=mysecret,src=/local/secret", "id=mypassword"]`

#### `cache-from` (array)

Additional cache sources for Docker build.

Example: `["my-base-image:latest"]`

#### `skip-pull-from-cache` (boolean, default: `false`)

Skip pulling from cache (useful for testing).

#### `save` (boolean, default: `true`)

Whether to save cache after build.

#### `restore` (boolean, default: `true`)

Whether to restore cache before build.

#### `max-age-days` (number, default: `30`)

Maximum age in days for cached images.

#### `cache-key` (string or array)

Custom cache key. If not provided, automatically generated from Dockerfile content and build context.

Example: `["my-key", "v1.0"]` or `"custom-key"`

#### `export-env-variable` (string, default: `BUILDKITE_PLUGIN_DOCKER_IMAGE`)

Environment variable name for exporting the final image reference.

#### `verbose` (boolean, default: `false`)

Enable verbose logging.

#### `tag` (string)

Custom tag for the cached image. If not provided, generated from git commit or pipeline context.

### ECR Provider Options

When using `provider: ecr`, these options are available:

#### `ecr.region` (string)

AWS region for ECR registry. If not provided, will be auto-detected from AWS configuration.

Example: `us-east-1`

#### `ecr.account-id` (string)

AWS account ID (12 digits). If not provided, will be auto-detected from AWS credentials.

Example: `123456789012`

#### `ecr.registry-url` (string)

Custom ECR registry URL. If not provided, will be constructed from account ID and region.

Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com`

### GAR Provider Options

**Note:** Authentication is handled by the `gcloud` CLI. Ensure your Buildkite agent has authenticated with Google Cloud before running this plugin (e.g., using a service account key or Workload Identity Federation).

When using `provider: gar`, these options are available:

#### `gar.project` (string, required)

Google Cloud project ID.

Example: `my-gcp-project`

#### `gar.region` (string, default: `us`)

GAR region.

Valid values: `us`, `europe`, `asia`, or specific regional endpoints like `us-central1-docker.pkg.dev`

Example: `us`

#### `gar.repository` (string)

Artifact Registry repository name. If not provided, defaults to the image name.

Example: `docker` (for repository name, results in full path like `us-docker.pkg.dev/project/docker/image`)

### Buildkite Packages Provider Options

**Note:** Authentication requires either a Buildkite API token with Read Packages and Write Packages scopes, or OIDC authentication using `buildkite-agent` (available in Buildkite pipeline jobs).

When using `provider: buildkite`, these options are available:

#### `buildkite.org-slug` (string)

Buildkite organization slug. If omitted, it will use the `BUILDKITE_ORGANIZATION_SLUG` environment variable.

Example: `my-org`

#### `buildkite.registry-slug` (string)

Container registry slug. If omitted, it defaults to the image name.

Example: `docker-images`

#### `buildkite.auth-method` (string, default: `api-token`)

Authentication method to use. Supported values: `api-token`, `oidc`.

- `api-token`: Uses the `api-token` parameter or falls back to `BUILDKITE_API_TOKEN` environment variable
- `oidc`: Uses `buildkite-agent oidc request-token` command (available in pipeline jobs)

#### `buildkite.api-token` (string)

Buildkite API token with Read Packages and Write Packages scopes. Required when `auth-method` is `api-token`. Can also be provided via the `BUILDKITE_API_TOKEN` environment variable for backward compatibility.

### Artifactory Provider Options

**Note:** Authentication requires a username (typically email) and identity token from your Artifactory instance.

When using `provider: artifactory`, these options are available:

#### `artifactory.registry-url` (string, required)

The Artifactory registry URL (e.g., `myjfroginstance.jfrog.io`). Do not include the protocol (`https://`).

#### `artifactory.username` (string, required)

The username for Artifactory authentication, typically your email address.

#### `artifactory.identity-token` (string, required)

The Artifactory identity token for authentication. Can reference an environment variable using `$VARIABLE_NAME` syntax.

#### `artifactory.repository` (string)

Artifactory repository name. If omitted, defaults to the image name.

### ACR Provider Options

**Note:** Authentication is handled by the Azure CLI (`az`). Ensure your Buildkite agent has authenticated with Azure before running this plugin. The authentication token has a 3-hour TTL, which is typically sufficient for CI/CD builds.

When using `provider: acr`, these options are available:

#### `acr.registry-name` (string, required)

The ACR registry name (not the full URL). The plugin will construct the full registry URL as `{registry-name}.azurecr.io`.

The registry name must be 5-50 alphanumeric characters and start with a letter.

Example: `myregistry` (results in `myregistry.azurecr.io`)

#### `acr.repository` (string)

ACR repository name. If omitted, defaults to the image name.

This allows you to organize cache images in a specific repository namespace.

Example: `docker-cache` (for repository name, results in full path like `myregistry.azurecr.io/docker-cache/image`)

## Authentication

### ECR Authentication

The plugin handles ECR authentication automatically using your existing AWS credentials. Make sure your build environment has AWS credentials configured through:

- IAM roles (recommended for EC2/ECS)
- AWS credentials file
- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

Required permissions:

- `sts:GetCallerIdentity`
- `ecr:GetAuthorizationToken`
- `ecr:DescribeRepositories`
- `ecr:CreateRepository`
- `ecr:BatchGetImage`
- `ecr:GetDownloadUrlForLayer`
- `ecr:BatchCheckLayerAvailability`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`

### GAR Authentication

The plugin uses gcloud for GAR authentication with your existing Google Cloud credentials. Make sure your build environment has Google Cloud credentials configured through:

- Service account keys
- Workload Identity (recommended for GKE)
- Application Default Credentials

Required permissions:

- `artifactregistry.repositories.get`
- `artifactregistry.repositories.create`
- `artifactregistry.docker.images.get`
- `artifactregistry.docker.images.push`
- `artifactregistry.docker.images.pull`

### Buildkite Packages Authentication

The plugin supports two authentication methods for Buildkite Packages:

#### API Token Authentication (Default)

Uses a Buildkite API token with Read Packages and Write Packages scopes:

```yaml
plugins:
  - docker-cache#v1.0.0:
      provider: buildkite
      image: my-app
      buildkite:
        org-slug: my-org
        api-token: $BUILDKITE_API_TOKEN
```

Or set the `BUILDKITE_API_TOKEN` environment variable in your build environment.

Required token scopes:
- `read_packages` - To pull cached images
- `write_packages` - To push new cache images

#### OIDC Authentication

Uses buildkite-agent OIDC tokens for passwordless authentication:

```yaml
plugins:
  - docker-cache#v1.0.0:
      provider: buildkite
      image: my-app
      buildkite:
        org-slug: my-org
        auth-method: oidc
```

OIDC authentication requires:
- buildkite-agent v3.38.0 or later
- Proper OIDC policy configuration in your Buildkite organization
- Pipeline access to the target registry

### ACR Authentication

The plugin uses the Azure CLI (`az`) for ACR authentication. Ensure your build environment has Azure credentials configured using one of the following methods:

- Service Principal credentials
- Managed Identity (recommended for Azure VMs/AKS)
- Azure CLI login (`az login`)

The plugin automatically runs `az acr login --name {registry-name}` to authenticate with your ACR registry.

Required Azure roles:
- `AcrPull` - To pull cached images from the registry
- `AcrPush` - To push new cache images to the registry

**Token Expiration:** ACR authentication tokens have a 3-hour TTL. This is typically sufficient for CI/CD builds. For longer-running builds, consider using Managed Identity which automatically refreshes tokens.

**Repository Auto-Creation:** Unlike some other registries, ACR automatically creates repositories on first push. No explicit repository creation is required.

## Cache Key Generation

Cache keys are automatically generated from:

- Dockerfile content hash (primary)
- Build context hash (if different from Dockerfile location)
- Build arguments
- Target stage (for multi-stage builds)

This ensures the cache is invalidated whenever anything that affects the build changes.

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----------: | :------------: |:---- |
| ✅ |  ✅ | ❌ | ✅ | **ECR** – Requires `awscli`<br/>**GAR** – Requires `gcloud`<br/>**ACR** – Requires `az` (Azure CLI)<br/>**Buildkite Packages** – Requires `docker`<br/>**Artifactory** – Requires `docker`<br/>**Hosted (Mac)** – Docker engine not available |

- ✅ Fully supported (all combinations of attributes have been tested to pass)
- ⚠️ Partially supported (some combinations cause errors/issues)
- ❌ Not supported

## Developing

To run tests, you can use the docker [Plugin Tester](https://github.com/buildkite-plugins/buildkite-plugin-tester):

```bash
docker run --rm -ti -v "${PWD}":/plugin buildkite/plugin-tester:latest
```

## License

MIT (see [LICENSE](LICENSE))
