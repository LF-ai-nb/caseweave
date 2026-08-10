# Security

CaseWeave is a local library and example program. It does not open network connections, execute generated tests, or write files by itself.

Please report security issues through a private repository advisory when the public repository is available. Until then, use the maintainer contact listed in the hackathon submission.

When adding features, treat these as security boundaries:

- do not execute generated values as code
- do not add network or filesystem access to the core library
- validate all model and constraint input before generation
- keep dependency licenses and sources documented
