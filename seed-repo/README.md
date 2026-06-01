# Sample Terraform Project — AI Code Review Demo

Esta es una "platform" Terraform de juguete que se usa como repo demo en GitLab.
Tiene problemas intencionales (security, cost, best-practices) para que el job
`ai-review` de Kiro CLI los detecte y comente en el Merge Request.

## Stages del CI

1. `validate` — `terraform fmt -check` + `terraform validate`
2. `ai-review` — Kiro CLI revisa el diff del MR y postea hallazgos como notas
3. `plan` — `terraform plan` (sólo si los anteriores pasan)

> Demo only. No deployar a prod.
