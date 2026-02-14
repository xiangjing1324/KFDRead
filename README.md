# KFDRead

最小可用的 KFD 读取模板，保留：
- 子进程入口（`-kfdread`）
- KFD 初始化 + 目标进程 Mach-O 头读取
- `Command+B` 自动产出 `.tipa`

## 目录结构

- `src/`：App 主代码
- `src/kfd/`：KFD 相关代码与依赖（集中管理）
  - `kfd.mm`
  - `kfd_c.h`
  - `YBKFD.hpp`
  - `libjailbreak.dylib`
  - `libchoma.dylib`
- `src/supports/Entitlements.plist`：签名权限
- `src/script.sh`：Run Script 打包脚本
- `packages/`：输出 `.tipa`

## 在新 Xcode 工程接入

1. 拖入 `src/kfd/` 下这 5 个文件到新工程 Target：
   - `kfd.mm`
   - `kfd_c.h`
   - `YBKFD.hpp`
   - `libjailbreak.dylib`
   - `libchoma.dylib`
2. 在 **Build Phases → Copy Bundle Resources** 确认包含：
   - `libjailbreak.dylib`
   - `libchoma.dylib`
3. 新建 **Run Script**，指向 `script.sh`（或直接粘贴脚本内容）。
4. 把 `ENABLE_USER_SCRIPT_SANDBOXING` 设为 `NO`。
5. 把 `CODE_SIGN_ENTITLEMENTS` 设为：
   - `src/supports/Entitlements.plist`

## 关键说明

- `-kfdread` 是必须入口：按钮点击后会 `posix_spawn` 拉起同一可执行文件新进程，再在子进程中执行 KFD 初始化和读取。
- 主进程只做 UI 和调度，避免主进程权限链不完整导致读取失败。
