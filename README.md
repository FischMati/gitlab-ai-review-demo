# GitLab + Kiro CLI: AI Code Review Demo en AWS

Demo end-to-end de **AI code review en pipelines de GitLab self-hosted**, usando
**Kiro CLI en modo `--no-interactive`** para revisar Merge Requests de Terraform y
publicar hallazgos como comentarios del MR.

> Patrón: agregar un stage `ai-review` en el pipeline de Terraform que corra
> Kiro CLI dentro de un runner/sandbox y devuelva comentarios (calidad,
> seguridad, optimización).

## Disclaimer

Este repositorio es un **prototipo con fines didácticos y demostrativos**. Su
objetivo es ilustrar el patrón de AI code review en pipelines de GitLab.

Es importante **no desplegar en producción sin la revisión adecuada.** La configuración
prioriza la simplicidad, e incluye código de ejemplo con problemas intencionales (ver `seed-repo/`). Antes de cualquier uso real, se debe realizar una revisión de seguridad, costos y buenas prácticas acorde al entorno.

## Arquitectura

```
┌──────────────────────────── AWS us-east-1 (default VPC) ────────────────────────────┐
│                                                                                     │
│   EC2 t3.large  "ai-review-demo-gitlab"            EC2 t3.medium "ai-review-demo-runner"│
│   └─ GitLab CE (Omnibus)  ◀──────HTTP/SSH──────▶  └─ gitlab-runner (shell)          │
│      EIP + SG :80,:443,:22                            └─ kiro-cli (--no-interactive)│
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
                   Demo project: terraform-platform
                          │
                          ▼
                   Pipeline (MR event):
                     1. terraform fmt + validate
                     2. ai-review:kiro  ──▶ kiro-cli chat --no-interactive
                                         └─▶ POST /merge_requests/:iid/notes
                     3. terraform plan
```

## Cómo correrlo

Pre-requisitos: AWS CLI con credenciales activas, `terraform`, `jq`, `git`,
`ssh`, `python3`.

```bash
# 0. Configurar secretos y variables locales (no se commitean)
cp .secrets/kiro_api_key.example .secrets/kiro_api_key   # pegar la Kiro API key
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
#   editar terraform.tfvars y definir allowed_admin_cidr con la IP/rango admin

# 1. Levantar GitLab + Runner (~10 min para que GitLab termine de inicializar)
./scripts/00-up.sh
./scripts/01-wait-gitlab.sh

# 2. Reset root password + crear PAT
./scripts/02-bootstrap-gitlab.sh

# 3. Crear proyecto y subir el repo Terraform "platform" + setear CI vars
./scripts/03-create-project.sh

# 4. Registrar el runner contra el proyecto
./scripts/04-register-runner.sh

# 5. Abrir un MR con un cambio "malo" para disparar el AI review
./scripts/05-open-mr.sh
```

Al finalizar, el script imprime la URL del MR. Al abrirla, el pipeline corre los
3 stages y en la pestaña **Discussion** del MR aparece la nota:

> ## Kiro AI Review
> ### Findings
> - **[SECURITY] network.tf — `aws_security_group.redis`** Permite 6379 desde 0.0.0.0/0…
> - **[SECURITY] cache.tf — `aws_elasticache_cluster.session`** No tiene `transit_encryption_enabled`…
> - **[BEST-PRACTICE] iam.tf — `aws_iam_role_policy.app`** Action `*` Resource `*` viola least privilege…

## Tear down

```bash
./scripts/99-down.sh
```
