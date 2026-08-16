# Security Audit

Inspect safe source and configuration files for concrete evidence of:

- Hard-coded credentials or sensitive values outside prohibited secret-bearing files.
- SQL, command, template, path, and deserialization injection.
- Unvalidated external input, unsafe shell execution, weak authorization, or missing authentication checks.
- Excessive IAM privileges, insecure defaults, unsafe network or temporary-file handling, and sensitive logging.
- Weak cryptography, unsafe token handling, vulnerable dependency evidence, and environment leakage.

Never read `.env*`, `*.tfvars`, files named for secrets, credentials, or tokens, private keys, authentication configuration, or secret-bearing environment values. It is acceptable to report that such a file exists without reading or exposing its contents.

Classify security evidence as one of:

- Confirmed vulnerability: the exploitable path is demonstrated by repository evidence.
- Likely vulnerability: the unsafe path is strong but runtime confirmation is missing.
- Unsafe pattern: the implementation increases exposure without proving exploitability.
- Hardening opportunity: defense-in-depth with no identified vulnerability.

For every security finding, state the attack surface, affected component, plausible impact, confidence limitation, and specific mitigation. Do not overstate exploitability or disclose sensitive values.
