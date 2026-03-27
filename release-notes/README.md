# Release Notes

Store one Markdown file per release tag in this directory.

Recommended naming:

- `v3.0.0.md`
- `v3.0.1.md`
- `v3.1.0.md`

Intended workflow:

- when a Git tag like `v3.1.0` is pushed
- the release workflow reads `release-notes/v3.1.0.md`
- that file becomes the GitHub release body

This keeps release messaging versioned, reviewable, and separate from the workflow YAML.
