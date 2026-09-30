# Contributing to NeoBili

[简体中文](#贡献指南)

Thanks for helping improve NeoBili. Bug reports, feature requests, documentation,
translations, and code contributions are welcome.

## Issues

Use [Issues](https://github.com/Fab1e2000/NeoBili/issues) to report bugs or suggest
features. Search existing issues first. For bugs, include the app version, device,
iOS version, steps to reproduce, and expected and actual behavior. Remove personal
information, credentials, and account details from logs and screenshots.

For large changes, open an issue to discuss the scope before starting.

## Pull requests

1. Fork the repository and create a feature or fix branch from the latest `develop`.
2. Keep each PR focused on one feature, fix, or related set of changes. Commit
   complete, understandable steps with clear messages.
3. Follow the [development and testing guide](docs/DEVELOPMENT.md) for setup,
   implementation, and checks. Update affected documentation with the code.
4. Open the PR with **`develop` as the base branch** and your working branch as the
   head branch. Ordinary contributions should target `develop`.
5. Explain the problem, the resulting behavior, and validation performed. Include
   screenshots for UI changes and distinguish passed, failed, skipped, and unrun
   checks. Fix relevant CI failures before the PR is merged.

If `develop` changes while your PR is open, update your branch when needed and
resolve conflicts. Ask for help in the PR if the intended behavior is unclear.

`main` holds stable release versions. Maintainers merge tested changes from
`develop` into `main` when preparing a release. A PR targeting `main` directly
should be agreed with a maintainer first, for example for an urgent release fix.
The branch workflow is maintained in the [development guide](docs/DEVELOPMENT.md#分支与合并).

## 贡献指南

欢迎提交问题反馈、功能建议、文档、翻译和代码改进。

### 问题反馈

请先搜索已有 [Issues](https://github.com/Fab1e2000/NeoBili/issues)，避免重复提交。
报告问题时附上 App 版本、设备、iOS 版本、复现步骤、预期行为和实际结果。
日志与截图请移除个人信息、凭据和账号资料。大范围改动请先开 Issue 讨论范围。

### 提交 PR

1. Fork 仓库，从最新的 `develop` 创建自己的功能或修复分支。
2. 一份 PR 聚焦一个功能、修复或一组相关改动；每次提交保存一个完整、可理解的小步骤。
3. 按[开发与测试指南](docs/DEVELOPMENT.md)配置环境、开发和验证，随代码更新受影响的文档。
4. 创建 PR 时，**目标分支（base）选择 `develop`**，来源分支（head）选择自己的工作分支。
5. 说明解决的问题、修改后的行为和验证结果。界面改动附截图；区分通过、失败、跳过和
   未执行的检查，合并前修复相关 CI 失败。

PR 期间若 `develop` 有新改动，按需更新自己的分支并解决冲突；不确定应该保留哪种行为时，
可以在 PR 中讨论。

`main` 保留稳定发布版本，由维护者在准备发版时将测试通过的 `develop` 合入。
直接向 `main` 提 PR 的特殊情况（例如紧急修复）请先与维护者确认。
完整分支约定见[开发指南](docs/DEVELOPMENT.md#分支与合并)。
