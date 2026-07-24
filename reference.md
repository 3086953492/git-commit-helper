# Commit Message Reference

只在需要选择 `type`、`scope`、正文重点或判断是否需要额外确认时读取本文件。

## 1. 规则优先级

按以下顺序决定格式：

1. 仓库的 `CONTRIBUTING*`、commitlint 或提交模板。
2. 最近 20 条提交形成的稳定惯例。
3. 本文件的默认 Conventional Commit 规则。

不要为了套用中文 scope 覆盖仓库已经稳定使用的英文或无 scope 风格。

## 2. `type` 判定

| type | 核心意图 |
|---|---|
| `feat` | 新功能、新能力或新模块 |
| `fix` | 修复错误行为、安全问题或边界缺陷 |
| `refactor` | 调整内部结构且外部行为不变 |
| `perf` | 性能优化 |
| `test` | 仅新增或调整测试 |
| `docs` | 仅更新文档 |
| `build` | 构建系统或依赖管理 |
| `ci` | CI/CD 流程 |
| `chore` | 其他维护性工作 |
| `revert` | 回滚既有提交 |

按主要业务意图选择，不按文件数量或扩展名选择。

## 3. `scope` 与 `subject`

- scope 可省略；有明确业务域时优先使用具体业务名，例如 `商品选项`、`订单状态`、`认证`。
- 不用 `工具函数`、`数据库`、`gorm` 等实现手段冒充业务域，除非仓库惯例如此。
- subject 概括结果或价值，避免“更新代码”“调整逻辑”“fix bug”。

示例：

```text
fix(订单状态): 统一状态值格式
refactor(认证): 收敛登录态恢复入口
docs: 补充生产部署步骤
```

## 4. 正文

正文只写 staged patch 中可证明的事实，按以下顺序排列：

1. 核心行为或能力。
2. 必要的接口、测试或兼容适配。
3. 锁文件、生成文件等被动更新。

标题与正文之间保留一个空行；bullet 之间不留空行。

## 5. 范围与确认门槛

只有出现 **ambiguous scope** 时请求额外确认，例如：

- `execute-mode` 下 staged 为空，且用户没有指定路径。
- `command-only` 下 staged 为空，且用户没有指定要暂存的路径。
- staged 同时包含明显无关的多个主题。
- 用户说“这些改动”，但当前目录存在多个可能仓库或多个独立 staged 批次。
- 需要把 untracked 文件加入提交，但文件可能包含配置、凭据或本地数据。
- 从 Windows 操作 WSL 仓库，但存在多个发行版且目标发行版无法从上下文确定。

以下情况不重复确认：

- 用户明确说“提交git”“帮我提交”或“按这个提交”。
- staged 范围单一且与当前任务一致。
- 用户已经确认了 message 或明确指定了提交路径。

## 6. 最终检查

- staged 范围与用户意图一致。
- type 按核心意图选择。
- message 没有描述 unstaged 内容。
- `git diff --cached --check` 已通过。
- 相关测试、构建或静态检查已完成。
- 检查、测试、临时 index、hooks 与 commit 使用同一个 Git 运行环境，没有混用 Windows Git 和 WSL Git。
- 当前平台执行器隔离并校验 staged tree；仅在 commit、父关系与 symbolic HEAD 均未漂移时对原分支 ref 做 CAS 撤回，并发 HEAD 或分支切换时不自动改写引用。
- 执行成功后已回读 `%H%n%B` 和最终 status。
