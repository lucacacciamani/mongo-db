# Contributing

Thanks for your interest in this project! It is a collection of guides and configuration files forrunning MongoDB 8.0 in Docker on Debian 13. The guides are written in Italian, but issues and pull requests in English are welcome.

## How you can help

- **Report errors**: a command that fails, an outdated step, a wrong path or a typo.
- **Report test results**: sections marked with 🧪 have not been tested on a real installation yet. If you run them, please share what happened (even if everything worked).
- **Suggest improvements**: clearer explanations, missing steps, better defaults.

## Opening an issue

Use one of the issue templates and include:

- the guide and section (e.g. `02-replica-set-guida-completa.md`, "Parte 4")
- your environment: Debian version, Docker / Docker Compose version, MongoDB version, cloud provider if
any
- the exact command you ran and its output (remove passwords, hostnames and IP addresses first)

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep changes focused: one topic per pull request.
3. If you change a command in a guide, update the matching file in `config/` (and vice versa). The full and quick versions of a guide should stay consistent.
4. Keep the existing style: Italian text, the 🧭 boxes for design choices, 📋 blocks for real test output, 🧪 for untested parts.
5. Shell scripts, YAML and systemd files must use LF line endings (enforced by `.gitattributes`).
6. Describe how you tested the change.

## Never commit secrets

Passwords, private keys (`*.key`, `*.pem`), certificates and backups must never end up in the repository.
Check your diff before committing. If a secret gets pushed by mistake, rotate it immediately and open an issue.
