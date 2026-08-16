# Finding Classification

## Severity

- **Critical:** Immediate credible risk of compromise, data loss or severe corruption, regulatory exposure, production outage, or catastrophic reliability failure.
- **High:** Material risk to correctness, security, reliability, scalability, governance, or maintainability.
- **Medium:** Important issue with bounded impact or a meaningful engineering weakness that should be scheduled.
- **Low:** Limited-risk improvement with modest impact.
- **Informational:** Verified context, strength, or optional refinement; do not include as a material finding unless useful.

## Confidence

- **High:** Direct evidence demonstrates the condition and its mechanism.
- **Medium:** Strong evidence exists, but runtime or organizational context could change the conclusion.
- **Low:** The observation requires measurement or external validation. Label it as such.

## Priority

- **P0:** Address immediately; active or imminent critical impact.
- **P1:** High material impact; prioritize next.
- **P2:** Important planned remediation.
- **P3:** Optimization or maintainability improvement.
- **P4:** Optional refinement.

Priority combines severity, confidence, business impact, technical risk, dependencies, and effort. It is not a direct severity alias.

## Effort

- **Small:** Typically no more than one engineer-day with localized change and validation.
- **Medium:** Typically two to five engineer-days or coordinated changes across a few components.
- **Large:** More than five engineer-days, material migration, or multi-team coordination.

State assumptions when repository evidence cannot support the estimate.
