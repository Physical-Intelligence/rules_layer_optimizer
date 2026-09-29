# External-consumer smoke module

This module imports the ruleset as an external dependency. Its initial
`library_readme` target validates module resolution without relying on root
module development dependencies. During extraction, add a minimal image build
and checks for public load paths, repository mappings, and tool resolution.
