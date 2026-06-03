# OpenClaw disaster recovery

Operational runbook for the OpenClaw stack on k3s (Operator + `OpenClawInstance` + Longhorn PVC).

## Prerequisites

- `kubectl` and cluster admin or namespace-scoped access to `openclaw` and `longhorn-system`
- `openclaw/scripts/openclaw.sh` on a machine with kubeconfig
- Vault password for `scripts/secrets.env` if you must recreate API secrets

---

## 1. Agent Pod evicted or deleted

**Symptom:** Pod `agent-primary-0` (or other instance) is missing; StatefulSet recreates it.

**Steps:**

1. `kubectl -n openclaw get pods -l app.kubernetes.io/name=openclaw -o wide`
2. `kubectl -n openclaw describe pod <pod-name>` for scheduling or image pull errors
3. If the instance CR is healthy, the Operator reconciles the StatefulSet. Wait for rollout:
   - `kubectl -n openclaw rollout status statefulset/agent-primary`
4. If CR is missing, re-apply from git and ensure secrets exist:
   - `./openclaw/scripts/openclaw.sh setup-secrets`
   - `kubectl apply -f openclaw/config/agent-primary.yaml`
   - `./openclaw/scripts/openclaw.sh create agent-primary` (recreates Ingress if needed)

PVCs are retained unless the `OpenClawInstance` or PVC is deleted.

---

## 2. PVC data corruption or bad state

**Symptom:** Agent starts but workspace or DB under `/data` is inconsistent.

**Preferred: Longhorn snapshot (same cluster)**

1. Longhorn UI → Volume for the OpenClaw PVC → **Snapshot** list → create or pick a snapshot before the incident
2. Follow Longhorn docs to **revert** or clone from snapshot to a new volume and reattach (procedure depends on Longhorn version)
3. If you clone to a new PVC, update the StatefulSet volume claim template only if you know the Operator’s reconciliation rules; often safer to restore in place via Longhorn revert

**If no good snapshot:** restore from remote backup (next section).

---

## 3. Cluster loss or volume loss — restore from S3 backup

**Prerequisites:** Longhorn **backup target** (S3-compatible) configured; `openclaw-daily-backup` RecurringJob completing successfully.

**High level:**

1. Install k3s, Longhorn, OpenClaw Operator (see `docs/deploy-plan.md` and `README.md`)
2. Recreate namespace and secrets: `./openclaw/scripts/openclaw.sh setup-secrets`
3. In Longhorn UI, **Backup** tab: find backups for the OpenClaw volume (group `openclaw`), restore to a PVC in `openclaw`
4. Deploy `OpenClawInstance` with `spec.restoreFrom` pointing at the restored volume **if** your Operator version supports restore-from-backup (see upstream docs for exact field)
5. If `restoreFrom` is not used, create the instance with the same name so the PVC name matches the restored volume, or follow operator guidance for binding an existing PVC

Always validate against the current [OpenClaw Operator CRD](https://openclaw.rocks/docs) for `restoreFrom` semantics.

---

## 4. Operator upgrade rollback

**Symptom:** Upgrade breaks reconciliation.

1. `helm -n openclaw-operator-system history openclaw-operator`
2. `helm -n openclaw-operator-system rollback openclaw-operator <revision>`
3. `kubectl -n openclaw-operator-system rollout status deploy/openclaw-operator`

## 4.1 Operator CrashLoopBackOff / cache sync timeout

**Symptom:** `openclaw-operator` 反复重启，日志里出现 `failed to wait for ... caches to sync`、`Informer to sync` 或 `CrashLoopBackOff`。

**处理顺序：**

1. 先确认控制面 API 与 DNS 正常。
2. 检查 `openclaw-operator` 所在节点是否资源过紧。
3. 适当提高 `manager` 容器的 CPU / memory requests 与 limits。
4. 执行 `kubectl rollout restart deploy/openclaw-operator -n openclaw-operator-system`。
5. 如果仍然卡住，删除当前 pod 让 Deployment 重新创建。

**本仓库当前做法：**

- 已将 `manager` 资源调到更宽松的档位，以减少 informer cache 同步超时。
- 如果后续再次出现类似问题，优先查看 `kubectl logs -n openclaw-operator-system deploy/openclaw-operator`。

---

## 5. Ingress / Tunnel

**Symptom:** UI unreachable via public hostname.

1. `kubectl -n openclaw get ingress`
2. Re-apply Ingress via `./openclaw/scripts/openclaw.sh create <agent-name>` (idempotent)
3. Cloudflare Tunnel / DNS: see `docs/CLOUDFLARE_TUNNEL_SETUP.md`

---

## 6. Related commands

| Action | Command |
|--------|---------|
| Health check | `./openclaw/scripts/openclaw.sh check` |
| Operator upgrade | `./openclaw/scripts/openclaw.sh upgrade` |
| Apply monitoring / backup jobs / quota | `./openclaw/scripts/openclaw.sh apply-infra` |
| Logs | `./openclaw/scripts/openclaw.sh logs agent-primary` |

---

## 7. PodDisruptionBudget

The Operator creates a **PodDisruptionBudget** per `OpenClawInstance` by default (`spec.availability.podDisruptionBudget`). Drain nodes with care: a single-replica agent may still block or allow disruption depending on `maxUnavailable`; see `kubectl -n openclaw get pdb`.
