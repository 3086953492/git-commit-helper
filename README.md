# Git Commit Helper

[中文](#中文) | [English](#english)

<a id="中文"></a>

## 中文

### 简介

Git Commit Helper 是一个面向 Codex 与其他兼容 Agent 的本地技能，用于根据 Git 改动生成、审阅或执行结构清晰的 commit。它优先分析暂存区，遵循仓库已有的提交风格，并在没有明确风格时采用 Conventional Commits。

本技能尤其适合 Windows PowerShell 环境，以及需要严格隔离 staged 与 unstaged 改动的提交场景。

### 功能亮点

- **暂存区优先**：提交说明只描述已确认的改动范围；同一文件中的未暂存改动不会混入目标 commit。
- **遵循仓库风格**：先参考近期提交；没有稳定惯例时，使用 `type(scope): subject` 风格。
- **三种意图模式**：可只生成 message、只生成安全命令，或检查后直接执行 commit。
- **安全执行器**：通过独立 index 快照、tree 校验、reflog 标记和并发保护降低误提交与重复提交风险。
- **PowerShell 中文友好**：commit message 以 UTF-8 Base64 传入脚本，避免多行文本和中文转义问题。

更多行为细节见 [SKILL.md](./SKILL.md)，完整场景见 [examples.md](./examples.md)，判断规则见 [reference.md](./reference.md)。

### 意图模式

| 模式 | 典型请求 | 行为 |
| --- | --- | --- |
| `message-only` | “写一个 commit message” | 只返回建议的 message，不修改 Git 状态 |
| `command-only` | “生成提交命令” | 范围明确后返回完整安全命令，不执行 |
| `execute-mode` | “帮我提交 Git” | 核对范围与状态后执行普通 commit |

### 环境要求

- Windows
- Windows PowerShell 5.1
- 可从命令行调用的 Git
- 支持本地技能目录的 Codex 或兼容 Agent 环境

### 安装

下载或克隆本仓库后，将整个 `git-commit-helper` 目录放入 Agent 的技能目录，并保留仓库内的文件结构。常见安装位置为：

```text
%USERPROFILE%\.agents\skills\git-commit-helper
```

可在 PowerShell 中检查关键文件是否就位：

```powershell
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"
Test-Path (Join-Path $skillRoot "SKILL.md")
Test-Path (Join-Path $skillRoot "scripts\commit.ps1")
```

两项都返回 `True` 后，即可在支持技能发现的 Agent 任务中使用。

### 使用方式

#### 通过 Agent 使用

可直接描述目标，也可以显式点名技能。例如：

```text
使用 $git-commit-helper，为当前 staged 改动写一个 commit message。
```

```text
使用 $git-commit-helper，生成安全的提交命令，但不要执行。
```

```text
使用 $git-commit-helper，检查并提交当前 staged 改动。
```

技能会先读取仓库状态与改动范围。若暂存区为空或路径范围不明确，执行模式会要求先确认范围，不会默认运行 `git add .`。

#### 直接调用脚本

当 commit message 已确定时，可在目标仓库根目录中通过已安装的 [scripts/commit.ps1](./scripts/commit.ps1) 调用安全执行器：

```powershell
$message = @'
feat(account): 支持用户头像更新

- 保存头像地址
- 补充更新场景测试
'@

$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
$messageBase64 = [Convert]::ToBase64String($messageBytes)
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"

& (Join-Path $skillRoot "scripts\commit.ps1") -Repository "." -MessageBase64 $messageBase64
```

脚本以调用时捕获的 staged 快照作为预期 tree；只有实际 commit tree 与其一致时，才会把提交视为安全完成。message 的内容与提交范围仍应在调用前完成审阅。

### 安全模型

- 不默认执行 `git add .`。只有用户明确指定路径或全部范围时，Agent 工作流才会逐路径暂存并重新检查。
- 在仓库外创建唯一临时目录，并通过 `GIT_INDEX_FILE` 使用真实 index 的独立快照。
- 在 commit 前以 `git write-tree` 记录预期 tree，并在 commit 后核对实际 tree；若 hook 使两者不一致，脚本会在安全条件满足时受保护地恢复原引用，或在状态不确定时停止并要求人工检查。
- 使用唯一 `GIT_REFLOG_ACTION` 识别本次创建的 commit，并检查 HEAD 是否发生并发移动。
- 只有在目标 commit 可被明确识别且引用状态仍安全时，才可能通过带旧值校验的 `update-ref` 恢复原引用；否则停止并保留现场供人工检查。
- Git 调用使用 `--no-pager`，避免等待交互式分页器。
- 脚本会在结束时尝试清理临时目录；若清理失败，会报告残留路径。若输出包含 `Do not retry commit`，commit 可能已经成功，必须先检查仓库，不能直接重试。

### 目录结构

```text
git-commit-helper/
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── commit.ps1
```

- [SKILL.md](./SKILL.md)：Agent 执行流程与硬性边界
- [examples.md](./examples.md)：常见 staged、unstaged 与混合状态示例
- [reference.md](./reference.md)：类型、scope、风险与验证参考
- [scripts/commit.ps1](./scripts/commit.ps1)：隔离 staged 快照的提交执行器

### 能力边界

- 只处理普通 commit，不执行 push、merge、rebase 或 amend。
- 发现冲突，或 merge、rebase、cherry-pick、revert 正在进行时，会停止普通提交流程。
- staged 为空且范围不明确时，需要用户选择路径；不会猜测要提交的文件。
- hooks 可以执行，但如果 hook 改变了预期 tree 或造成状态不确定，脚本会拒绝把结果当作安全完成。
- 清理失败或 HEAD 状态不明确时，请按错误信息检查仓库；看到 `Do not retry commit` 时不要重复运行。

<a id="english"></a>

## English

### Overview

Git Commit Helper is a local skill for Codex and other compatible agents. It generates, reviews, or executes well-scoped Git commits from the current changes. It analyzes the staging area first, follows the repository's existing commit style, and falls back to Conventional Commits when no clear convention exists.

The skill is designed for Windows PowerShell workflows and for repositories where staged and unstaged changes must remain strictly separated.

### Highlights

- **Staged-first analysis**: The commit message describes only the confirmed scope; unstaged edits in the same file stay out of the intended commit.
- **Repository-aware style**: Recent commits are preferred as the style guide; otherwise the skill uses `type(scope): subject`.
- **Three intent modes**: Generate only a message, generate a safe command without running it, or verify and execute a commit.
- **Guarded executor**: An isolated index snapshot, tree verification, reflog tagging, and concurrency checks reduce accidental or duplicate commits.
- **PowerShell-safe messages**: Commit text is transported as UTF-8 Base64, avoiding quoting problems with multiline or non-ASCII messages.

See [SKILL.md](./SKILL.md) for the complete behavior, [examples.md](./examples.md) for end-to-end scenarios, and [reference.md](./reference.md) for decision rules.

### Intent modes

| Mode | Example request | Behavior |
| --- | --- | --- |
| `message-only` | “Write a commit message” | Returns a suggested message without changing Git state |
| `command-only` | “Generate the commit command” | Returns a complete safe command once scope is clear, without running it |
| `execute-mode` | “Commit these changes” | Verifies scope and repository state, then creates an ordinary commit |

### Requirements

- Windows
- Windows PowerShell 5.1
- Git available from the command line
- Codex or another compatible agent environment that discovers local skills

### Installation

Download or clone this repository, then place the entire `git-commit-helper` directory in your agent's skills directory without changing its internal structure. A common installation path is:

```text
%USERPROFILE%\.agents\skills\git-commit-helper
```

Verify the required files in PowerShell:

```powershell
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"
Test-Path (Join-Path $skillRoot "SKILL.md")
Test-Path (Join-Path $skillRoot "scripts\commit.ps1")
```

When both commands return `True`, the skill is ready for an agent environment that supports skill discovery.

### Usage

#### Use through an agent

Describe the desired outcome directly or name the skill explicitly. For example:

```text
Use $git-commit-helper to write a commit message for the currently staged changes.
```

```text
Use $git-commit-helper to generate a safe commit command, but do not run it.
```

```text
Use $git-commit-helper to verify and commit the currently staged changes.
```

The skill inspects repository state and scope first. If nothing is staged or the path scope is ambiguous, execute mode asks for confirmation instead of defaulting to `git add .`.

#### Invoke the script directly

Once the commit message is final, run the installed guarded executor [scripts/commit.ps1](./scripts/commit.ps1) from the target repository root:

```powershell
$message = @'
feat(account): support avatar updates

- persist the avatar URL
- cover the update flow with tests
'@

$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
$messageBase64 = [Convert]::ToBase64String($messageBytes)
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"

& (Join-Path $skillRoot "scripts\commit.ps1") -Repository "." -MessageBase64 $messageBase64
```

The staged snapshot captured when the script starts defines the expected tree. A commit is treated as safely completed only when its tree matches that snapshot. Review the message and intended scope before invoking it.

### Safety model

- It does not default to `git add .`. The agent workflow stages only explicit paths, followed by a fresh review, when the user has clearly selected paths or the complete scope.
- It creates a unique temporary directory outside the repository and uses `GIT_INDEX_FILE` with an isolated copy of the real index.
- Before committing, `git write-tree` records the expected tree and the resulting commit tree is checked afterward. If a hook makes them differ, the script performs a guarded ref restore when safe or stops for manual inspection when state is uncertain.
- A unique `GIT_REFLOG_ACTION` identifies the commit created by the invocation, while HEAD movement is checked for concurrent changes.
- A ref can be restored with an old-value-guarded `update-ref` only when the created commit and ref state are unambiguous; otherwise the script stops and preserves the state for inspection.
- Git runs with `--no-pager`, preventing waits on an interactive pager.
- The script attempts to clean up its temporary directory at the end and reports the retained path if cleanup fails. If output contains `Do not retry commit`, a commit may already exist; inspect the repository before doing anything else.

### Repository structure

```text
git-commit-helper/
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── commit.ps1
```

- [SKILL.md](./SKILL.md): agent workflow and hard boundaries
- [examples.md](./examples.md): common staged, unstaged, and mixed-state examples
- [reference.md](./reference.md): type, scope, risk, and verification guidance
- [scripts/commit.ps1](./scripts/commit.ps1): executor for an isolated staged snapshot

### Scope boundaries

- The skill handles ordinary commits only; it does not push, merge, rebase, or amend.
- It stops the ordinary commit flow when conflicts exist or a merge, rebase, cherry-pick, or revert is in progress.
- If the staging area is empty and scope is unclear, the user must select paths; the skill does not guess which files belong in the commit.
- Hooks may run, but if a hook changes the expected tree or leaves repository state uncertain, the script refuses to treat the result as safely completed.
- If cleanup fails or HEAD state is unclear, inspect the repository as instructed by the error. Never rerun the command after a `Do not retry commit` warning.
