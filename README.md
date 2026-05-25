# HAUT SRun Auto Login

河南工业大学（HAUT）校园网 OpenWrt / ImmortalWrt 路由器端自动认证脚本。

基于：

- https://github.com/zu1k/srun

实现：

- 自动等待校园网网络
- 自动登录认证
- 掉线检测
- 定时重登
- 多账号轮换
- 自动检测无线接口
- 日志自动维护
- OpenWrt / ImmortalWrt 兼容

适用于：

- OpenWrt
- ImmortalWrt
- 其它支持 `sh/ash` 的路由器系统

---

# 功能特性

## 自动网络检测

启动后自动等待校园网服务器可达（默认为嵩山路校区校园网认证地址，请自行修改脚本中的认证地址）：

```text
172.16.154.130
```

避免路由器开机后网络未初始化导致认证失败。

---

## 自动检测无线接口

自动检测：

- `phy1-sta0`
- `phy0-sta0`

并自动写入：

```json
"if_name"
```

无需手动修改配置。

---

## 自动认证

网络可用后自动执行：

```bash
srun login
```

实现无人值守认证。

---

## 掉线检测（Watchdog）

后台守护进程会周期检测网络状态：

- 网络正常 → 保持在线
- 网络异常 → 自动重新认证

默认检测目标：

```text
baidu.com
```

---

## 多账号轮换

支持多个校园网账号。

当检测到掉线时：

- 自动切换下一个账号
- 自动重新登录

适用于：

- 多人共享
- 多账号负载
- 单账号限制在线时长

---

## 定时重登

默认：

```text
3 分钟
```

自动执行一次重登。

用于避免：

- 校园网长时间在线掉线
- NAT 状态异常
- 深澜认证卡死

---

## 日志自动维护

自动清理：

- 登录日志
- Watchdog 日志

避免日志无限增长占满闪存。

---

# 项目结构

```text
/srun
├── haut-srun.sh
├── srun
├── config.json
├── config1.json
├── config2.json
├── accounts.list
├── srun_main.log
├── srun_watchdog.log
└── srun_state.log
```

---

# 安装教程

# 1. 创建目录

```bash
mkdir /srun
```

---

# 2. 上传文件

将以下文件上传到：

```text
/srun
```

包括：

- `haut-srun.sh`
- `srun`
- `config.json`

如果使用多账号：

- `config1.json`
- `config2.json`
- `accounts.list`

---

# 3. 添加执行权限

```bash
chmod +x /srun/haut-srun.sh
chmod +x /srun/srun
```

---

# 4. 配置账号

## 单账号

编辑：

```text
/srun/config.json
```

---

## 多账号

创建：

```text
/srun/accounts.list
```

内容示例：

```text
config1.json
config2.json
```

然后分别创建：

```text
/srun/config1.json
/srun/config2.json
```

---

# 5. 配置开机自启动

编辑：

```text
/etc/rc.local
```

添加：

```bash
(sleep 2 && /srun/haut-srun.sh start) &
```

保存后重启路由器即可。

---

# 使用方法

## 启动

```bash
/srun/haut-srun.sh start
```

---

## 手动登录

```bash
/srun/haut-srun.sh login
```

---

## 切换账号登录

```bash
/srun/haut-srun.sh login_next
```

---

## 启动 Watchdog

```bash
/srun/haut-srun.sh watchdog
```

---

## 查看状态

```bash
/srun/haut-srun.sh status
```

---

# 日志文件

## 主日志

```text
/srun/srun_main.log
```

记录：

- 登录
- 重登
- 账号切换
- 接口检测

---

## Watchdog 日志

```text
/srun/srun_watchdog.log
```

记录：

- 网络检测
- 掉线状态
- Watchdog 运行情况

---

## 状态文件

```text
/srun/srun_state.log
```

记录：

- 上次登录时间
- 当前账号
- 重连次数

---

# 配置模板

## config.json

```json
{
  "username": "你的学号",
  "password": "你的密码",
  "ac_id": "5",
  "domain": "",
  "if_name": "phy1-sta0"
}
```

---

# 注意事项


建议：

```text
config.json
config1.json
config2.json
accounts.list
```

加入：

```text
.gitignore
```

---

## 需要使用对应架构的 srun 二进制文件

例如：

- mips
- mipsel
- arm
- aarch64
- x86_64

请根据路由器架构选择。

---

# 致谢

## SRun Core

- https://github.com/zu1k/srun

---

# License

MIT License
