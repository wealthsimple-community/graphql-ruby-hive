# Contributing

## Development

```
bundle install
bundle exec rake spec
bundle exec rubocop
```

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`chore:`, etc.) for PR titles. [release-please](https://github.com/googleapis/release-please)
parses these to determine the next version and generate `CHANGELOG.md`, so PR titles matter more
than individual commit messages on branches merged via squash.

## Releasing

Releases are automated:

1. Merging a PR to `main` triggers [release-please](https://github.com/googleapis/release-please),
   which opens or updates a "release PR" bumping `lib/graphql-hive/version.rb` and `CHANGELOG.md`
   based on Conventional Commits merged since the last release.
2. Merging that release PR creates a git tag and GitHub Release, which triggers the `publish` job
   in [`.github/workflows/release.yml`](.github/workflows/release.yml) to build and push the gem to
   [RubyGems.org](https://rubygems.org/gems/graphql-hive) via OIDC trusted publishing.

No manual `gem push` or version bump is needed — don't edit `version.rb` by hand.
