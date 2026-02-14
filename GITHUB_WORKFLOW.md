# GitHub 管理方案（Xcode 模板工程）

## 推荐做法（最稳）

不要每次“新建 Xcode 项目再覆盖文件”，而是直接把当前工程当模板仓库：

1. `git clone` 模板仓库
2. 在 Xcode 里改 `PRODUCT_BUNDLE_IDENTIFIER`、`PRODUCT_NAME`
3. 改 `kTargetName`（目标进程名）
4. `Command+B` 直接出 `.tipa`

这样不会反复处理默认 `main/viewcontroller` 差异，也避免 `project.pbxproj` 丢引用。

## 分支建议

- `main`：稳定模板
- `feature/*`：功能开发
- `release/*`：可发包版本

## 新项目建议

如果是“新 app 名称/新包名”，建议：

- 从 `main` 拉分支：`git checkout -b app-xxx`
- 改 bundle id / app name / 图标
- 保持 KFD 内核链路文件不动（`kfd.mm`, `YBKFD.hpp`, `main.m`）

## 上传到 GitHub

```bash
git init
git add .
git commit -m "init minimal KFD template"
git branch -M main
git remote add origin <你的仓库URL>
git push -u origin main
```
