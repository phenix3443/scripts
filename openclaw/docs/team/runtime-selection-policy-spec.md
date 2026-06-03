# Runtime Selection Policy Spec

## 1. 目标

定义在 AI 软件工程团队中如何确定 Project Runtime 的实现策略。

核心原则：

- 当前架构只保留 `Project Runtime`
- Master 不绑定单一具体实现
- Hermes 是第一阶段默认 Project Runtime 实现

## 2. 选择维度

- 是否需要长期项目记忆
- 是否需要长期驻场服务
- 是否需要直接与用户持续沟通
- 是否需要跨 repo 长期维护
- 是否需要维护项目级项目管理工具

## 3. Hermes

适合：

- 长期项目维护
- 多 repo 项目
- 项目经验持续积累
- 长期保留 `MEMORY.md`
- 持续对接项目管理工具
- 当前阶段默认对接 GitHub Project

不适合：

- 单次临时任务
- 不需要长期记忆的纯执行型任务

## 4. 默认策略

第一阶段默认：

- 每个项目绑定一个长期 `Project Runtime`
- 默认实现：`Hermes`

## 5. Master 选择方式

Master 不需要在多种 Runtime 类型之间做动态选型。

建议：

- 每个项目预先绑定一个 Project Runtime
- Master 只做项目到 Runtime 的路由
- Runtime 内部如果需要额外工具或执行器，由 Runtime 自己决定

## 6. 推荐模型

```mermaid
flowchart LR
  P[Project]
  M[OpenClaw Master]
  H[Hermes]

  M --> P
  P --> H
```

## 7. 结论

推荐：

- 架构层只保留 `Project Runtime`
- 第一阶段使用 `Hermes` 作为默认实现
- 让 Master 保持调度层中立，不把设计写死到某个实现
