# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this package, please report it privately rather than filing a public issue.

**To report:** Open a [private security advisory](https://github.com/sreyamaram/similar-insights-semantic-matching/security/advisories/new) on this repository.

Please include:

- A description of the vulnerability and the potential impact
- Steps to reproduce (including org configuration, sample data, and version)
- Any mitigations you've identified

You can expect an initial acknowledgment within 5 business days. We'll work with you on a fix and coordinate disclosure.

## Scope

This is a Salesforce metadata package that runs entirely in the customer's org. It makes no external callouts and handles no sensitive data beyond what the org already stores. In-scope concerns include:

- Apex SOQL injection or CRUD/FLS bypasses
- LWC DOM XSS via untrusted insight content
- Permission set granting access beyond declared intent
- Flow or Prompt Template prompt-injection risks once Einstein is wired up

Out of scope:

- Vulnerabilities in the underlying Life Sciences Cloud managed package (`lsc4ce`) — report those to Salesforce
- Vulnerabilities in Salesforce Platform itself — report to [security@salesforce.com](mailto:security@salesforce.com)
