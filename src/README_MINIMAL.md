# KFDRead Minimal Template

这是最小可用模板，只保留以下核心：

- `kfd.mm`：YuanBao 同款 KFD 初始化与读取链路
- `YBKFD.hpp`：核心 KFD 工具函数
- `main.m`：`-kfdread` 子进程入口
- `ViewController.m`：按钮触发 + persona 提权拉起子进程
- `script.sh`：`Command+B` 自动签名并打包 `.tipa`
- `supports/Entitlements.plist`：YuanBao 同款权限
- `libjailbreak.dylib` / `libchoma.dylib`：运行依赖

目录约定：

- `src/`：所有源码与构建脚本
- `src/supports/Entitlements.plist`：默认签名权限
- `packages/`：`Command+B` 输出 `.tipa`

## 为什么必须 `-kfdread`

是必须的。按钮点击后会 `posix_spawn` 拉起同一个可执行文件的新进程，
并通过 persona 99 设置 `uid=0/euid=0`。  
KFD 初始化在这个子进程里执行，主进程只负责 UI 和启动流程。

## 你可以改的地方

- 目标进程名：`ViewController.m` 里的 `kTargetName`
- 产物路径：`packages/KFDRead_*.tipa`

## TestKFD 是否可直接跑

可以。建议直接 `git clone` 本仓库后在现有工程改：

- `PRODUCT_BUNDLE_IDENTIFIER`
- `PRODUCT_NAME`（可改成 `TestKFD`）

不建议“新建空工程再覆盖”，那样容易漏掉 `project.pbxproj` 里的 Run Script、资源与编译设置。
