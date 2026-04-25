# Rotor

> Desktop-first 的开源 2FA 客户端：让 TOTP 码停留在你工作的屏幕上，而不是手机里。

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](#)

🇬🇧 [English README](README.md)

---

## 为什么有 Rotor

主流 TOTP 应用都在手机上。当你正在桌面登录某个服务时：拿起手机 → 解锁 → 打开 authenticator → 盯着屏幕念 6 位数 → 输入。Rotor 把它倒过来 — 你的验证码常驻 macOS 菜单栏，点一下就在。

**差异化：**

- **macOS 菜单栏常驻**：点击图标弹出 popover，所有码就在眼前（对标 Raycast / Stats / Raivo OTP）
- **窗口全局置顶**：主窗口和 popover 各自独立开关
- **完全兼容** Google Authenticator / Aegis / 2FAS 的导入导出
- **纯本地**：无云后端、无账号系统、无遥测

---

## 功能

### 已实现（MVP）

- 添加账户：粘贴 `otpauth://` URI **或** 拖入二维码图片（支持多选批量识别）
- TOTP 显示：30 秒倒计时圆环、Courier Prime 数字 3+3 分组
- 点击复制；60 秒后剪贴板自动清空（带 hash 校验，不会覆盖你期间复制的其他东西）
- 菜单栏图标（template 图，自动适配 dark mode），左键 popover、右键菜单
- 编辑 / 删除账户、手动拖拽排序、分组、搜索、按名称 / 最近添加 / 自定义排序
- 全局置顶开关（主窗口 / popover 独立）
- 加密本地导出 / 导入（`.rotor` 格式：**Argon2id** + AES-256-GCM；兼容旧版 PBKDF2 v1 备份）
- 第三方备份导入：
  - Google Authenticator `otpauth-migration://` 二维码（项目内置 protobuf 解析）
  - Aegis JSON（未加密）
  - 2FAS JSON（未加密）
- 可选**保护模式**：主密码经 Argon2id 派生 KEK，AES-GCM 包裹磁盘上的 vault 密钥，可设空闲自动锁定（1 / 5 / 15 / 60 分钟）
- 屏幕录制 / 截图防护（`NSWindow.sharingType = .none`）
- 跟随系统的浅 / 深色

### 后续规划

- HOTP / Steam Guard
- iCloud 同步
- 浏览器扩展联动
- 移动端

---

## 安装

### 从 Release 下载

1. 在 [Releases](../../releases) 页找匹配你 Mac 的 DMG：
   - Apple Silicon → `Rotor-<version>-apple-silicon.dmg`
   - Intel → `Rotor-<version>-intel.dmg`
2. 双击 DMG，把 Rotor.app 拖进 Applications
3. **第一次启动**：当前是 ad-hoc 签名，macOS Gatekeeper 会拦下。在 Rotor.app 上右键 → "打开" → "打开" 一次即可。之后正常启动

### 从源码构建

```bash
git clone https://github.com/deskotp/rotor.git
cd rotor
open rotor.xcodeproj
# 选 "rotor" scheme，⌘R
```

要求：

- macOS 26（Tahoe）或更新
- Xcode 26 或更新（项目 deployment target = `26.3`）

---

## 存储与安全

### 文件位置

数据落在 App Sandbox 容器：

```
~/Library/Containers/com.liasica.rotor/Data/Library/Application Support/
├── default.store           # SwiftData（账户元数据 + 密文）
├── default.store-shm
├── default.store-wal
├── vault.key               # 32 字节随机密钥，保护模式关闭时使用
└── vault.master            # JSON envelope，保护模式开启时使用
```

### 保护模式关闭（默认）

- `vault.key` 是 32 字节随机 AES-256 密钥，权限 `0600`
- TOTP secret 用此密钥 AES-GCM 加密后存入 `default.store`
- 攻击者拿到磁盘还要这两个文件配合；只能算混淆，不算强保护

### 保护模式开启

- `vault.master` 是 JSON envelope：
  ```json
  {
    "version": 1,
    "kdf":     { "name": "argon2id", "salt": "<base64>", "opsLimit": 3, "memLimit": 67108864 },
    "nonce":   "<base64>",
    "ciphertext": "<base64>"
  }
  ```
- 主密码 → **Argon2id**（64 MiB / 3 轮，RFC 9106 v1.3）→ 256-bit KEK
- KEK + AES-256-GCM → 包裹 32 字节的 vault 密钥
- 主密码**从不**落盘；vault 密钥只在内存里活，锁定时被清除
- 主密码丢失后**无法恢复**账户。请妥善保管

### 备份（`.rotor` 文件）

- 与 `vault.master` 同一 envelope 形态；`version: 2` 用 Argon2id，`version: 1`（早期导出）用 PBKDF2-SHA256（600,000 轮），两种都能读
- 导入时所有 secret 都用目标机器的 vault key 重新加密

### 兼容性

Rotor 能导入：
- 自己的 `.rotor` 文件（v1 PBKDF2 / v2 Argon2id）
- Google Authenticator 的 `otpauth-migration://` 二维码（零依赖自实现 protobuf 解析）
- Aegis JSON（未加密版）
- 2FAS JSON（未加密版）

加密的 Aegis / 2FAS 备份请先在原 app 里解密导出。

---

## 开发

### 项目结构

```
rotor/
├── Core/                     # 领域逻辑（TOTP、vault、各种 importer / service）
├── Design/                   # 设计 tokens（颜色、字体）
├── Views/                    # SwiftUI 视图
├── Vendor/Reorderable/       # 内联的 visfitness/Reorderable，已为 macOS 修补
├── Fonts/                    # 内置 Courier Prime（OFL 协议）
├── Assets.xcassets/          # 应用图标 / 主色 / 菜单栏图标
└── rotorApp.swift            # 入口
.design/                       # 设计源（icon、mark、sketch 导出）
.github/workflows/release.yml # CI：双架构 build + DMG
```

### 协作规范

- 所有 commit 消息和源代码注释都用**英文**（CLAUDE.md §6.1）
- 用户面向的 UI 字符串保持中文（项目首要受众）；后续再做英文本地化
- Conventional Commits：`feat:` / `fix:` / `refactor:` / `docs:` / `chore:` / `perf:` / `ci:`
- `master` 始终保持可发布；功能开发走 `feat/xxx` 分支

### 发布

推一个 `v*` 形式的 tag，GitHub Actions 自动 build 双架构、发布到 Releases。

```bash
git tag v0.1.0
git push origin v0.1.0
```

---

## License

GPL-3.0，详见 [LICENSE](LICENSE)。

内置字体 [Courier Prime](https://github.com/quoteunquoteapps/CourierPrime) 使用 SIL Open Font License，见 `rotor/Fonts/OFL.txt`。

---

## 致谢

- [visfitness/Reorderable](https://github.com/visfitness/reorderable) — 拖拽排序原语（已 vendor 进项目并 patch 适配 macOS）
- [jedisct1/swift-sodium](https://github.com/jedisct1/swift-sodium) — Argon2id 等密码学原语
- TOTP / OTP 标准：[RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238)、[RFC 4226](https://datatracker.ietf.org/doc/html/rfc4226)
- Argon2id 参数选取参考 [RFC 9106](https://datatracker.ietf.org/doc/html/rfc9106) 与 OWASP Password Storage Cheat Sheet
