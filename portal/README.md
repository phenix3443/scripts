# 公司门户自动检测与登录

在公司网络下，未认证时访问外网会被重定向到门户认证页，需输入用户名密码才能上网。本目录提供脚本：**自动检测是否被重定向到门户**，若需要则**自动提交登录表单**，可定时或手动执行。

## 前置条件

- `curl`
- 已在浏览器中成功登录过该门户，并能抓取到登录请求（见下方「如何抓取登录参数」）

## 快速开始

1. **复制并编辑配置与凭证**

   ```bash
   cd portal
   cp portal.conf.example portal.conf
   cp portal.secret.example portal.secret
   chmod 600 portal.secret
   # 编辑 portal.conf：填写 PORTAL_BASE_URL、PROBE_URL、PORTAL_URL_PATTERN、LOGIN_ENDPOINT、表单字段名等
   # 编辑 portal.secret：填写 PORTAL_USERNAME、PORTAL_PASSWORD
   ```

2. **（可选）自签名证书**

   若门户使用自签名 HTTPS，需让 curl 跳过证书校验：

   ```bash
   export CURL_OPTS="-k"
   ```

3. **运行**

   ```bash
   chmod +x portal-auto-login.sh
   ./portal-auto-login.sh run    # 检测 + 需要时登录
   ./portal-auto-login.sh check  # 仅检测是否需要登录
   ./portal-auto-login.sh login  # 强制尝试登录一次
   ```

## 如何抓取登录参数

门户服务器在内网，无法从公网直接访问，需要你在**已连公司 Wi-Fi 且被重定向到门户时**在浏览器中抓一次请求：

1. 打开门户登录页（或从访问 baidu.com 被重定向过去的那页）。
2. 按 **F12** 打开开发者工具，切到 **Network**，勾选 **Preserve log**。
3. 输入用户名、密码，点击登录。
4. 在 Network 里找到**提交登录的那条请求**（多为 **POST**，名称可能是 login、doLogin、auth 等）。
5. 右键该请求 → **Copy** → **Copy as cURL (bash)**。
6. 从复制的 cURL 中提取：
   - **请求 URL**：填入 `portal.conf` 的 `LOGIN_ENDPOINT`（若为完整 URL 可直接写完整地址）。
   - **Request Headers**：若除 `Content-Type` 外还有 `Origin`、`Referer` 等，门户可能校验，脚本当前使用 `Content-Type: application/x-www-form-urlencoded`；若仍失败可再对照 cURL 补全。
   - **Body 参数名**：表单里用户名、密码对应的字段名，填入 `USERNAME_FIELD`、`PASSWORD_FIELD`（常见为 `username`/`password`）。
   - 若有固定或动态参数（如 `ac-ip`、`uaddress`、`umac`），可填入 `EXTRA_POST_PARAMS`（与抓包一致）。

7. **探测 URL**：你希望用哪个地址判断「是否需要登录」就填 `PROBE_URL`（如 `http://www.baidu.com`）。若最终被重定向到的 URL 里包含 `PORTAL_URL_PATTERN`，脚本会认为需要登录。

## 配置说明

| 变量 | 说明 |
|------|------|
| `PORTAL_BASE_URL` | 门户根 URL，如 `https://192.168.222.250:19008` |
| `PROBE_URL` | 探测用 URL，未认证时会被重定向到门户 |
| `PORTAL_URL_PATTERN` | 判定「被重定向到门户」的 URL 特征字符串 |
| `LOGIN_ENDPOINT` | 登录接口路径或完整 URL（与抓包一致） |
| `USERNAME_FIELD` / `PASSWORD_FIELD` | 表单字段名 |
| `EXTRA_POST_PARAMS` | 可选，额外 POST 参数 |

凭证放在 `portal.secret`（不提交 Git），或使用环境变量 `PORTAL_USERNAME`、`PORTAL_PASSWORD`。

## 定时执行（仅建议在公司环境启用）

可与 systemd timer 配合，定期检测并在需要时登录：

```bash
# 安装（需 root）
sudo ./portal-timer.sh install

# 查看状态
./portal-timer.sh status

# 卸载
sudo ./portal-timer.sh uninstall
```

安装时会从 `portal.service.example`、`portal.timer.example` 生成 systemd 单元（每 10 分钟执行一次）。若门户使用自签名证书，可在 `portal.service.example` 中取消 `Environment="CURL_OPTS=-k"` 的注释后重新安装。

## 验证码说明

若门户登录前有**图形/滑块验证码**，当前脚本无法自动通过，需考虑：

- 浏览器自动化（如 Selenium/Playwright）在本地打开登录页，人工完成验证码后再由脚本填表提交；或
- 仅在无验证码或验证码可 bypass 的环境使用本脚本。

## 安全与合规

- 密码仅存放在本机 `portal.secret` 或环境变量，不要提交到 Git。
- 若公司策略禁止自动登录或明文保存密码，请改用合规方式（如手动登录一次后长期有效则不自动填密）。
