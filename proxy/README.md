# VPS 代理节点

当前目录用于辅助管理海外 VPS 上的 `ppanel-node` 部署变量，以及保留旧 `sing-box` 脚本做历史清理参考。当前生产方案已经切换到 `ppanel-node`，不再使用 `0-proxy-node.yml` 这套旧剧本。

## 节点列表

| 主机名 | 节点名称 | 地址 | 位置 |
|--------|----------|------|------|
| netcup | netcup-us | v2202506281468351398.goodsrv.de | 🇺🇸 US |
| netcup-nl | netcup-nl | v2202602281468431064.bestsrv.de | 🇳🇱 NL |

## 当前方案

- **节点执行体**: `ppanel-node`
- **部署方式**: Ansible + `ansible-vault`
- **实际 playbook**: `ansible/playbooks/vps/0-ppanel-node.yml`
- **主机变量来源**: `ansible/inventory/host_vars/<host>.yml`
- **必需变量**: `ansible_become_password`、`ppanel_node_server_id`、`ppanel_node_secret_key`

## 快速开始

```bash
cd /path/to/home-lab

# 1. 初始化单台主机变量
./proxy/scripts/manage-keys.sh set netcup \
  --server-id 2 \
  --secret-key 12345678 \
  --become-password 'your-sudo-password'

# 2. 部署（全部节点）
ansible-playbook -i ansible/inventory/vps.yml \
  ansible/playbooks/vps/0-ppanel-node.yml \
  --vault-password-file ansible/.vault_pass

# 3. 部署（单节点测试）
ansible-playbook -i ansible/inventory/vps.yml \
  ansible/playbooks/vps/0-ppanel-node.yml \
  --limit netcup \
  --vault-password-file ansible/.vault_pass
```

## 文件结构

```
proxy/
├── README.md                        # 本文档
└── scripts/
    ├── manage-keys.sh               # host_vars 维护工具
    └── sing-box.sh                  # 旧 sing-box 脚本，仅保留作历史清理参考

ansible/
├── inventory/vps.yml                # VPS 清单
├── inventory/host_vars/             # 每台 VPS 的加密变量
├── playbooks/vps/0-ppanel-node.yml  # ppanel-node 部署 playbook
├── playbooks/vps/9-uninstall-ppanel-node.yml
├── templates/vps/
│   ├── PPanel-node.service.j2
│   └── ppanel-node-config.yml.j2
└── group_vars/vps_nodes.yml         # 共享默认变量
```

## 脚本说明

### manage-keys.sh — 主机变量管理

```bash
./proxy/scripts/manage-keys.sh <command>

# 查看
list                    # 列出 inventory 中的 VPS 及 host_vars 状态
show <host>             # 查看某台 VPS 的解密后变量
template <host>         # 输出未加密模板

# 操作
set <host> ...          # 创建或更新某台 VPS 的 host_vars
delete <host>           # 删除某台 VPS 的 host_vars
```

**依赖**: ansible-vault, yq

### sing-box.sh — 历史脚本

这份脚本不再参与当前 `ppanel-node` 部署，只在需要清理旧 `sing-box` 现场时保留参考。

## 常用操作

### 设置单台主机变量

```bash
./proxy/scripts/manage-keys.sh set netcup \
  --server-id 2 \
  --secret-key 'replace-with-real-secret' \
  --become-password 'replace-with-sudo-password'
```

### 查看当前主机变量

```bash
./proxy/scripts/manage-keys.sh show netcup
```

### 部署单台节点

```bash
ansible-playbook -i ansible/inventory/vps.yml \
  ansible/playbooks/vps/0-ppanel-node.yml \
  --limit netcup \
  --vault-password-file ansible/.vault_pass
```

### 卸载单台节点

```bash
ansible-playbook -i ansible/inventory/vps.yml \
  ansible/playbooks/vps/9-uninstall-ppanel-node.yml \
  --limit netcup \
  --vault-password-file ansible/.vault_pass
```

## 故障排查

```bash
# 查看服务状态和日志
ssh netcup
sudo systemctl status PPanel-node
sudo journalctl -u PPanel-node -n 50 --no-pager

# 检查端口和防火墙
sudo ss -tlnp | grep ppnode
sudo ufw status

# 查看远端配置
sudo sed -n '1,120p' /etc/PPanel-node/config.yml

# 批量检查所有节点
for h in netcup netcup-nl; do
  echo "==> $h"; ssh $h "sudo systemctl status PPanel-node --no-pager -l"
done
```
