# Security Policy

## Scope

This repository contains documentation and configuration files, not a software product. Security issues
that are relevant here include, for example:

- a guide or configuration file that leads to an insecure setup (e.g. MongoDB exposed to the internet,
authentication disabled, weak TLS settings)
- a script that leaks credentials or handles them insecurely (e.g. passwords in command lines, logs or
world-readable files)
- secrets accidentally committed to the repository

Vulnerabilities in MongoDB, Docker or Debian themselves should be reported to their respective projects:
[MongoDB](https://www.mongodb.com/docs/manual/tutorial/create-a-vulnerability-report/),
[Docker](https://www.docker.com/trust/vulnerability-disclosure-policy/),
[Debian](https://www.debian.org/security/).

## Supported versions

Only the current content of the `main` branch is maintained. The guides target MongoDB 8.0 on Debian 13.

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private reporting instead:
**Security** tab → **Report a vulnerability**.

Include the affected guide or file, the section, and a description of the risk. You will receive an
acknowledgement as soon as possible, and the fix will be published once it is ready. Reporters are
credited in the fix unless they prefer otherwise.
