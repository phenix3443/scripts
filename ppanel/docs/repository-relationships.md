# PPanel 仓库关系梳理

> 本文只分析 `perfect-panel` 组织下当前未归档的仓库。已归档仓库不纳入范围。

## 结论先行

PPanel 生态可以分成三层理解：

1. 核心运行时：`server`、`frontend`、`ppanel-node`
2. 发布与配套：`ppanel`、`ppanel-script`、`ppanel-docs`、`subscription-template`、`ppanel-assets`
3. 迁移与生态：`migrate`、`XrayR`、`rules`

其中，真正的主链路是：

`frontend` <-> `server` <-> `ppanel-node`

其余仓库大多是在做镜像发布、部署脚本、订阅模板、文档、迁移工具或规则资产同步。

## 仓库分组

| 仓库 | 角色定位 | 关系说明 |
| --- | --- | --- |
| `server` | 核心后端 | PPanel 的业务中枢，负责面板服务本身 |
| `frontend` | 核心前端 | 现行 Web 面板界面，与 `server` 形成前后端主链路 |
| `ppanel-node` | 节点侧组件 | 部署在节点/VPS 侧，向 `server` 拉取配置并回传状态 |
| `ppanel` | 镜像与发行包装 | 把 `server` 的发布产物和运行时二进制打成 Docker 镜像 |
| `ppanel-script` | 部署脚本 | 提供快速部署、拉取和整理发布文件的脚本 |
| `ppanel-docs` | 文档仓库 | 主要承载官方文档与说明材料 |
| `subscription-template` | 订阅模板 | 提供订阅输出模板或模板素材 |
| `ppanel-assets` | 资源资产 | 为面板或配套前端提供静态资源 |
| `migrate` | 迁移工具 | 用于从 V2board 等旧系统迁移到 PPanel |
| `XrayR` | 相关生态 | Xray 后端框架，属于节点/代理生态的关联项目 |
| `rules` | 规则镜像仓库 | 同步上游规则、脚本和 geo 数据，不属于 PPanel 核心代码 |

## 主要关系

### 1. `server` 是核心后端

`server` 是 PPanel 的业务中心，其他仓库大多围绕它展开。

- `frontend` 通过 API 对接 `server`
- `ppanel-node` 通过 API 与 `server` 交互
- `ppanel` 和 `ppanel-script` 都是在围绕 `server` 的发布产物做封装和分发

### 2. `frontend` 是当前 Web 门面

`frontend` 提供用户和管理界面，是面板的前端入口。

- 它依赖 `server` 提供业务 API
- 它不承担节点逻辑，也不负责二进制发布

### 3. `ppanel-node` 是节点侧执行体

`ppanel-node` 负责在 VPS 或节点机器上运行，和 `server` 形成控制端/执行端关系。

- `server` 下发节点配置
- `ppanel-node` 负责拉取配置、启动协议服务、上报状态

这意味着它不是面板本身，而是面板的节点代理组件。

### 4. 镜像构建链路

这组仓库在 home-lab 里对应的镜像，不是手工随便指定出来的，而是上游 release / workflow 的产物：

- `perfect-panel/server` 的 `release.yml` 由 `push tags: ['v*']` 触发，发布 `ppanel-server` 二进制并推送 `ppanel-server` 镜像
- `perfect-panel/ppanel` 的 `release.yml` 由 `repository_dispatch` 的 `trigger-build` 事件触发，接收外部传入的 `tag`，再拉取 `perfect-panel/server` 的 release，把 `gateway` 与 `ppanel-server` 打包成 `ppanel/ppanel` 镜像；从 Actions 运行历史看，最近一批触发者是 `LeifDraven`，但在当前已克隆的相关仓库里没找到显式发送这个 dispatch 的 workflow，推测来源是手动 API 调用或未克隆的自动化脚本
- `perfect-panel/frontend` 的 `release.yml` 由 `push` 到 `main` / `next` / `beta` / `develop` 触发，执行 `semantic-release` 生成前端 release 产物；当前公开 workflow 里能明确看到的是 `ppanel-admin-web` 和 `ppanel-user-web` 的 release 包，和你在集群里使用的前端镜像版本相对应

因此在本仓库里可理解为：

- `server` -> `ppanel/ppanel:v0.1.18`
- `frontend` -> `ppanel/ppanel-admin-web:v1.4.2`
- `frontend` -> `ppanel/ppanel-user-web:v1.4.2`
- `mysql` / `redis` -> 外部基础镜像，不属于 perfect-panel 自构建

### 5. `ppanel` 更像发行打包仓库

从仓库内容看，`ppanel` 不是源码主仓库，而是发布与分发包装层：

- `script/server.sh` 会去拉 `perfect-panel/server` 的最新 release
- `Dockerfile` 会把 `gateway` 与 `ppanel-server` 二进制打入镜像
- 发布工作流负责构建并推送 `ppanel/ppanel` 镜像

因此它更准确的定位是：

> `server` 的镜像发布仓库 + 运行配置样例仓库

### 6. `rules` 是规则资产同步仓库

`rules` 也不是 PPanel 核心实现，而是规则分发和同步仓库。

它的上游主要来自三类项目：

- `Blackmatrix7/ios_rule_script`
- `MetaCubeX/meta-rules-dat`
- `VirgilClyne/GetSomeFries`

仓库里的 `blank/`、`external/`、`rewrite/`、`rule/`、`script/`、`geo/`、`ruleset/` 都是同步镜像目录。

所以 `rules` 的用途是：

- 为代理客户端提供规则与 geo 数据
- 通过 GitHub Actions 定时同步上游内容
- 作为静态规则资产仓库供外部分发引用

它和 PPanel 的关系是生态层面的，不是核心代码层面的。

### 7. `ppanel-script`、`subscription-template`、`ppanel-assets` 属于配套层

这几个仓库都不直接承担核心业务逻辑，但会被部署、展示或订阅链路使用。

- `ppanel-script`：偏安装、下载、打包、快速部署
- `subscription-template`：偏订阅结果输出格式
- `ppanel-assets`：偏静态资源与配套素材

### 8. `migrate` 和 `XrayR` 属于迁移/生态层

- `migrate` 面向旧系统迁移，解决的是“从哪里来”的问题
- `XrayR` 是更底层的 Xray 后端生态项目，和 PPanel 处于相邻层级

## 简化关系图

```mermaid
flowchart LR
  frontend[frontend]
  server[server]
  node[ppanel-node]
  ppanel[ppanel]
  script[ppanel-script]
  docs[ppanel-docs]
  template[subscription-template]
  assets[ppanel-assets]
  migrate[migrate]
  xrayr[XrayR]
  rules[rules]

  frontend <--> server
  server <--> node
  ppanel --> server
  script --> server
  docs --> frontend
  docs --> server
  server --> template
  server --> assets
  migrate --> server
  node --> xrayr
  rules -. 生态配套。-> frontend
  rules -. 规则资产。-> node
```

## 对 home-lab 的实际意义

结合本仓库里的部署方式，可以把这些上游仓库理解成：

- `server`：面板后端镜像和核心能力来源
- `frontend`：当前正在用的 Web 界面来源
- `ppanel-node`：VPS 节点上运行的执行体
- `ppanel`：把 `server` 打包成可直接用的 Docker 镜像
- `ppanel-admin-web` / `ppanel-user-web`：由 `frontend` 的 release workflow 构建出来的前端镜像
- `rules`：给客户端生态提供规则资产，与面板核心部署是两条线

如果只看“面板是否能工作”，优先关注的是：

1. `server`
2. `frontend`
3. `ppanel-node`
4. `ppanel`

如果是“代理客户端体验”或“规则分发”，再看 `rules`、`subscription-template`、`ppanel-assets`。

## 已排除的仓库

以下仓库已归档，因此不纳入本文关系图：

- `ppanel-web`
- `ppanel-user-web`
- `ppanel-admin-web`
