# Distroless contract

These packages use a synthetic apt repository and no pip hub.

- `apt`: an inferred package keeps its lockfile size and appears in the archive.
- `env_merge`: base, inferred, and extra PATH entries join with a colon.
- `env_conflict`: the same variable from two sources fails analysis when it has no separator.
