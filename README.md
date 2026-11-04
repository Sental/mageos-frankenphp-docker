# mageos-frankenphp-docker

Base images for running Mage-OS on [FrankenPHP](https://frankenphp.dev), published on Docker Hub as
[`sental90/mageos-frankenphp-docker`](https://hub.docker.com/r/sental90/mageos-frankenphp-docker).

They hold the operating system, PHP, its extensions and the tools to build a store. Nothing in them
belongs to one project: no config files, no entrypoint, no code. The images built on top add those.

## The images

| Image | Contains | Used for |
| --- | --- | --- |
| `runtime` | FrankenPHP on Debian 13, supervisor, logrotate, the PHP extensions below | the base of every staging and production image |
| `build` | `runtime` plus git, unzip, Node and npm, Composer, and Xdebug installed but not enabled | CI builds the store on it; the dev image is `build` with Xdebug enabled |

The extensions: bcmath, gd, intl, pdo_mysql, soap, sockets, xsl, zip, opcache, igbinary, redis, imagick,
pcntl, ftp and mbstring, plus sodium from PHP itself.

Each image lists what it holds, versions included:

```bash
docker run --rm --entrypoint cat sental90/mageos-frankenphp-docker:8.5-build \
    /usr/local/share/mageos-frankenphp/versions.txt
```

Xdebug is only installed in `build`, so CI never loads it. To turn it on, add an ini file with
`zend_extension=xdebug` (the dev image's `xdebug.ini` does), or run `docker-php-ext-enable-xdebug`.

## Tags

There are images for PHP 8.3, 8.4 and 8.5. Each publish pushes four tags for one PHP version, all with
the same UTC datetime:

| | Moving | Immutable |
| --- | --- | --- |
| runtime | `8.5-runtime` | `8.5-runtime-202611041530` |
| build | `8.5-build` | `8.5-build-202611041530` |

- **Dev** uses the moving tags, so it always has the newest image for its PHP version.
- **CI, for staging and production,** uses the immutable tags. Renovate in the project bumps the datetime
  when a newer one is published, so a new base reaches production only after staging has built on it.

Every image is labelled with the commit it was built from (`org.opencontainers.image.revision`), when
(`created`), its datetime (`version`), and the exact FrankenPHP image it was built on, digest included
(`base.name`).

## How they're kept up to date

There's one branch per PHP version, and `main`:

- **`main`** holds everything shared: the Dockerfile, the workflows and their scripts, `renovate.json` and
  this README. It never builds images.
- **`php8.3`, `php8.4`, `php8.5`** each hold everything from `main`, plus one file of their own,
  `base.Dockerfile`, which names that version's FrankenPHP base and nothing else:

  ```dockerfile
  FROM dunglas/frankenphp:1.13.4-php8.3-trixie@sha256:…
  ```

What happens:

1. **A shared change lands on `main`:** your own push, or a Renovate pull request you merge there. On
   `main`, Renovate bumps the pinned PECL extensions, Xdebug and Composer, and the GitHub Actions versions.
2. **`sync` opens a pull request from `main` into each version branch that's behind,** unless one is
   already open: an open one follows `main` by itself.
3. **Upstream changes arrive on the version branches directly.** Renovate keeps each `base.Dockerfile`
   current: the version on a FrankenPHP release, and the digest when upstream rebuilds the same tag. It
   does that daily, whenever its own base changes, for PHP patch releases and Debian fixes. Without the
   digest those rebuilds would be invisible, because the tag's name doesn't change.
4. **Every pull request into a version branch** runs the `test` job of `image`: it builds both images and
   checks them (`.github/scripts/check.sh`), and publishes nothing.
5. **Merging it publishes** that version's four tags.

Three rules keep the branches from drifting:

- **Merge sync pull requests with a merge commit,** never squash or rebase. Otherwise the branch doesn't
  record `main`'s commits as merged, and the next sync replays all of `main`'s history. The ruleset below
  allows only merge commits on the version branches.
- **Shared files change only on `main`.** On the version branches, Renovate touches `base.Dockerfile` and
  nothing else.
- **`base.Dockerfile` never exists on `main`.** A merge from `main` therefore leaves it alone.

## Setting it up

Once, in this order: the publish job needs its environment the first time a version branch is pushed.

### 1. The sync app

`sync` opens its pull requests as a GitHub App. A pull request opened with a workflow's own token starts
no other workflows, so it would get no test build.

1. Your settings → Developer settings → GitHub Apps → New GitHub App.
2. Name it (for example `mageos-frankenphp-sync`), set the homepage URL to this repository, and untick
   **Active** under Webhook.
3. Repository permissions: **Contents: Read-only** and **Pull requests: Read and write**. Nothing else.
4. Where can this GitHub App be installed: **Only on this account**. Create it.
5. Note its **Client ID**, then generate a private key, which downloads a `.pem` file.
6. Install the app on this repository only.
7. In this repository: Settings → Secrets and variables → Actions → New repository secret:
   `SYNC_APP_CLIENT_ID` (the Client ID) and `SYNC_APP_PRIVATE_KEY` (the whole `.pem` file).

### 2. A Docker Hub token

Docker Hub → Account settings → Personal access tokens → generate one with **Read & Write**. Make the
Docker Hub repository public, so anyone can pull without logging in.

### 3. One environment per version

Settings → Environments → New environment, named exactly like the branch (`php8.3`, `php8.4`, `php8.5`):

- Deployment branches and tags: **Selected branches**, then the branch of the same name.
- Variable `php_string`: the version, for example `8.3`.
- Secrets `DOCKERHUB_USERNAME` (`sental90`) and `DOCKERHUB_TOKEN`.

Only a job running on that branch can use the environment, so only a merge into a version branch can
publish. Pull requests never see the Docker Hub token.

### 4. The version branches

Create each from `main` and give it its `base.Dockerfile`:

```bash
git switch -c php8.3 main
printf 'FROM dunglas/frankenphp:1.13.4-php8.3-trixie\n' > base.Dockerfile
git add base.Dockerfile
git commit -m "Name the PHP 8.3 base"
git push -u origin php8.3
```

That push publishes the branch's first images. Renovate's first pull request on the branch then pins the
digest.

### 5. A ruleset for the version branches

Settings → Rules → Rulesets → New branch ruleset:

- Target branches: include by pattern, `php*`.
- Bypass list: Repository admin, so your own pushes to a version branch still go through.
- **Require a pull request before merging**, with allowed merge methods: **Merge** only.
- **Require status checks to pass:** `test`.

### 6. Renovate

Install the [Renovate app](https://github.com/apps/renovate) on this repository. It reads `renovate.json`
from `main` and works on `main` and every `php*` branch. Automerge is off, so every update waits for you.

To check `renovate.json` after editing it, using the validator in Renovate's own image:

```bash
docker run --rm -v "$PWD:/repo:ro" -w /repo --entrypoint renovate-config-validator renovate/renovate --strict
```

## Adding a PHP version

1. Add its environment (step 3).
2. Create its branch with its `base.Dockerfile` (step 4). The push publishes its first images.

Nothing else needs to change: `sync`, Renovate and the ruleset all match any `php*` branch. To retire a
version, delete its branch and environment; the tags already published stay.

## Building locally

On a version branch:

```bash
docker buildx build --target runtime -t local/runtime:8.5 \
    --build-context upstream=docker-image://$(sed -n 's/^FROM //p' base.Dockerfile) .
docker buildx build --target build -t local/build:8.5 \
    --build-context upstream=docker-image://$(sed -n 's/^FROM //p' base.Dockerfile) .
bash .github/scripts/check.sh local/runtime:8.5 local/build:8.5
```

On `main`, which has no `base.Dockerfile`, name a base directly, for example
`--build-context upstream=docker-image://dunglas/frankenphp:1.13.4-php8.5-trixie`. To try a local image
in a project, point the project's `FROM` at it.

## Why it's built this way

- **The Dockerfile never names its base.** The base differs per branch, and Renovate can only keep it
  current if it's written out in a file. `FROM upstream` with a build context keeps it out of the shared
  file, needs no `ARG`, and fails the build if the context is missing.
- **`base.Dockerfile` has a digest.** Upstream rebuilds its tags under the same name, and the digest is
  the only thing that changes when it does.
- **Xdebug is installed but not enabled.** Dev needs it; CI and production never load it. That's one
  image instead of two.
- **The PECL extensions are pinned.** They're not part of the base image's digest, so without a pin,
  their updates would arrive unannounced. Pinned, each one is a pull request.
- **Moving and immutable tags.** Dev follows the newest image. Staging and production move only when the
  dated tag is bumped, and staging builds on it before production does.
