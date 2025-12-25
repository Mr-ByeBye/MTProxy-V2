# MTProxy-V2 一键脚本（mtg）

这是一个用于快速部署 Telegram MTProto 代理的脚本项目，底层使用 [9seconds/mtg](https://github.com/9seconds/mtg)（MTProxy v2 生态，FakeTLS）。

## 功能

- 一键安装/卸载 mtg（二进制 + systemd 服务）
- 一键启动/停止/重启、修改端口/密钥、查看状态
- 输出订阅链接（tg:// 与 https://t.me/proxy）
- 可选安装快捷命令：在 SSH 里输入 `mtproxy` 直接呼出菜单
- 多用户管理：创建多个用户实例（不同端口、不同订阅链接），支持删除/启停/查看状态

## 环境要求

- Linux（需要 systemd）
- root 权限
- 可访问 GitHub（用于下载 mtg release 与配置模板）
- 依赖命令：curl 或 wget、tar、systemctl

## 安装与运行

在服务器上执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Mr-ByeBye/MTProxy-V2/main/mtproxy.sh)
```

进入菜单后：

- 选择 `1. 安装MTproxy`
- 按提示输入伪装域名与监听端口
- 安装完成后会输出两条订阅链接（推荐保存）

## 快捷命令（推荐）

如果你希望后续在 SSH 里随时输入命令呼出菜单：

- 在脚本菜单选择 `13. 安装快捷命令(mtproxy)`
- 之后在 SSH 里直接输入：

```bash
mtproxy
```

卸载这个快捷入口：

- 在脚本菜单选择 `14. 卸载快捷命令(mtproxy)`

说明：卸载快捷命令只会删除 `mtproxy` 这个入口，不会卸载 mtg 服务本体；卸载 mtg 请用菜单 `2. 卸载MTproxy`。

## 多用户管理

mtg 设计上只使用单个 secret，因此这里的“多用户”通过“多实例（不同端口）”实现：每个用户一个独立配置与一个独立 systemd 实例。

操作入口：

- 主菜单选择 `15. 多用户管理`

支持操作：

- 创建用户：输入用户名、伪装域名、端口（默认会自动推荐递增端口）
- 列出用户：显示用户名、端口、运行状态
- 输出用户订阅链接：按用户名输出该用户对应链接
- 删除用户：停止并移除该用户实例
- 启动/停止/重启/查看状态：按用户名操作对应 systemd 实例

落地文件与服务：

- 用户配置目录：`/etc/mtg/users/`
- 用户配置文件：`/etc/mtg/users/<用户名>.toml`
- 用户服务模板：`/etc/systemd/system/mtg-user@.service`
- 用户服务名：`mtg-user@<用户名>.service`

## 常用 systemd 命令（可选）

主实例：

```bash
systemctl status mtg
systemctl restart mtg
```

某个用户实例（例如 alice）：

```bash
systemctl status mtg-user@alice
systemctl restart mtg-user@alice
```

## 目录结构（脚本默认）

- mtg 二进制：`/usr/bin/mtg`
- 主配置文件：`/etc/mtg.toml`
- 主服务文件：`/etc/systemd/system/mtg.service`

## 开源依赖

- [9seconds/mtg](https://github.com/9seconds/mtg)

