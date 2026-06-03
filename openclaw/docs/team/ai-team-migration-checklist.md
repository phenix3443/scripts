# AI Team Migration Checklist

## 1. 目标

将 AI team 相关定义从 `home-lab` 仓库拆分到独立仓库：

- `womenlia/ai-team`

同时保留：

- `home-lab` 继续作为基础设施与 Flux 部署仓库

## 2. 当前已完成

- Team 设计与实施文档已集中到 `openclaw/docs/team/`
- 本地已初始化 `womenlia/ai-team` 仓库骨架
- `home-lab` 已准备 Flux 外部仓库接入骨架：
  - `fluxcd/clusters/ai-team-source.yaml`
  - `fluxcd/clusters/production/ai-team.yaml`

## 3. 下一步迁移顺序

1. 将 `openclaw/docs/team/` 同步到 `womenlia/ai-team`
2. 在 `womenlia/ai-team` 中建立运行时配置目录
3. 将 Master/Hermes 的声明性配置迁移到 `womenlia/ai-team`
4. 提交并推送 `womenlia/ai-team`
5. 在 `home-lab` 中启用 Flux 对 `womenlia/ai-team` 的同步
6. 完成后逐步删除 `home-lab` 中重复的 team 定义

## 4. 启用前提

在启用 `ai-team` 的 Flux Kustomization 之前，应先确认：

- GitHub 仓库 `womenlia/ai-team` 已创建
- 仓库内容已推送到 `main`
- `fluxcd/clusters/production/ai-team.yaml` 中的 `path` 指向正确目录
- 该目录下存在可被 Flux 渲染的清单

## 5. 当前安全策略

当前 `ai-team` Flux Kustomization 默认为：

- `suspend: true`

这样做的目的是：

- 先把接入骨架提交到 `home-lab`
- 在 `womenlia/ai-team` 仓库内容准备好之前，不影响现有集群
