---
name: git-commit-helper
description: 根据 Git 改动生成或审阅提交消息；用户要求“提交git”“帮我提交”或“生成提交命令”时，按请求提供命令或执行普通提交。
---

# Git Commit Helper

根据改动与已有上下文写出准确、简洁的提交消息。只在用户明确要求时提供命令或执行提交。

## 职责与请求模式

| 请求 | 行为 |
|---|---|
| “写 commit message”“审阅这条提交消息” | `message-only`：只输出消息或修改建议，不修改 Git 状态 |
| “生成提交命令” | `command-only`：输出完整命令，不执行 |
| “提交git”“帮我提交” | `execute-mode`：范围明确后直接调用提交脚本，不重复请求确认 |

本技能不承担代码验收：不主动运行或建议测试、构建、lint、静态检查、代码审查，也不修复周边问题。用户另外要求的验证或仓库明确规定的要求属于独立任务，不因调用本技能而重跑；仓库 hooks 按原配置执行。

## 读取足够的信息

- 用户已提供 diff 或待润色的消息时，直接据此处理；仅生成文本不必访问仓库。
- 需要查看本地改动时，复用本轮已取得且没有变化迹象的范围和 diff。缺少时才读取 `git status --short --branch` 和目标 diff；仓库位置不明时才用 `git rev-parse --show-toplevel` 定位。
- staged 非空时，以 `git diff --cached` 为提交范围；不把 unstaged/untracked 改动混入消息。仅生成消息且 staged 为空时，可读取 `git diff` 和相关 untracked 文件，并简短注明范围。
- 不固定读取 stat、name-status、check、完整文件或提交历史，也不在生成消息后再次通读 diff。只有用户改变范围、暂存内容发生变化或命令报错需要定位时，才补读受影响部分。
- diff 和已有上下文足以解释改动时直接写消息。只有具体语义不清时才补读相关内容；staged 文件使用 `git show :<path>`，旧版本使用 `git show HEAD:<path>`，调用关系可用 `git grep --cached`。不例行追踪调用链或历史，不创建固定的“意图简报”。

## 写消息

遵循用户指定格式或已知仓库规范。风格未知且确有必要时，只查看少量近期标题；无需每次重新找配置或读取固定数量的历史提交。没有明确惯例时使用中文 Conventional Commit：

```text
<type>(<可选 scope>): <具体改动或结果>
```

小改动可以只有标题。正文只补充标题容纳不下的行为、原因或兼容性信息；允许保留必要的文件名、字段名和数值，不要求固定 bullet、影响声明或“被动更新”。不要编造性能、安全、体验收益或测试通过结论。需要类型示例时再读 [reference.md](reference.md)。

范围与可观察结果清楚时直接继续，不因商业动机未知或措辞有多种选择而询问。只有无法保守表述且会实质改变提交含义，或提交范围确实不明确时，才问一个具体问题。多个主题可建议拆分，但用户已明确要求一起提交时尊重该选择，不擅自重建或部分取消 index。

## 提供命令或执行提交时

- staged 为空时，使用用户本次或此前已明确指定的路径／全部改动范围；命令中使用显式 `git add -- <paths>`，仅 `execute-mode` 实际暂存，失败时不继续提交。范围仍不清楚才询问，不默认 `git add .`。暂存前已读过的相同内容无需再读一遍；新纳入的内容才需要补读。
- staged 非空时保留现有边界；部分暂存的文件不得通过整文件 `git add` 混入其他改动。
- 使用目标仓库实际所属的 Git 环境：Windows Git 用 [scripts/commit.ps1](scripts/commit.ps1)，WSL/Linux/macOS Git 用 [scripts/commit.sh](scripts/commit.sh)。具体调用语法按需读 [examples.md](examples.md) 对应平台小节。
- 从 Windows 控制 WSL 时，沿用已明确的发行版；无法确定时才询问。用该发行版的 `wslpath` 转换 Windows 路径，保持读取、暂存和提交使用同一套 Git。
- 脚本负责提交事务内的 Git 状态检查、index 隔离和结果回读。不要在脚本前后复制这些步骤；脚本不能运行时报告原因，不自行换成裸 `git commit`。
- 本技能只执行普通 commit，不执行 push、merge、rebase 或 amend；空 staged、冲突或正在进行的 Git 操作交由脚本拒绝并说明。
- 根据脚本返回的 hash、message 和 status 报告结果，不再次运行 log/status。失败或状态不确定时先理解输出；提示 `Do not retry commit` 时，不自动重试。

## 输出

- `message-only`：只给消息或审阅建议；必要时一句话注明分析范围。
- `command-only`：给可执行命令，仅补充必要的路径或环境说明。
- `execute-mode`：给 hash、提交消息和剩余改动状态；失败时说明实际结果及阻塞原因。

不附带固定检查清单、运行环境报告或验证建议。
