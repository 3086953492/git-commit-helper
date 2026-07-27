# Git Commit Helper

[中文](#中文) | [English](#english)

<a id="中文"></a>

## 中文

### 简介

Git Commit Helper 是一个面向 Codex 与其他兼容 Agent 的跨平台本地技能，用于根据 Git 改动还原改动目的与影响，再生成、审阅或执行结构清晰的 commit。它优先分析暂存区，遵循仓库已有的提交风格，并在没有明确风格时采用 Conventional Commits。

本技能支持 Windows PowerShell、WSL、Linux 与 macOS，并在所有受支持环境中严格隔离 staged 与 unstaged 改动。

### 功能亮点

- **暂存区优先**：提交说明只描述已确认的改动范围；意图调查使用 index/HEAD 安全视图，同一文件中的未暂存改动不会混入目标 commit。
- **意图优先**：结合用户上下文、测试、调用关系、契约与相关历史，先回答“为什么改、行为如何变化、会影响谁”，避免把 diff 改写成文件清单。
- **零交互优先**：证据支持唯一合理解释时直接继续；只有多个解释会改变提交语义时，才询问一个最小必要问题。
- **遵循仓库风格**：先参考近期提交；没有稳定惯例时，使用 `type(scope): subject` 风格。
- **三种请求模式**：可只生成 message、只生成安全命令，或检查后直接执行 commit。
- **双原生执行器**：Windows 使用 PowerShell，WSL/Linux/macOS 使用 Bash；两者共享独立 index 快照、tree 校验、reflog 标记和并发保护。
- **跨 shell UTF-8 安全**：PowerShell 通过 Base64，Bash 通过 quoted heredoc、message 文件或 Base64 安全传递多行与非 ASCII message。
- **WSL 环境隔离**：检查、hooks、临时 index 和 commit 始终在同一个 WSL 发行版内完成，不混用 Windows Git。

更多行为细节见 [SKILL.md](./SKILL.md)，完整场景见 [examples.md](./examples.md)，判断规则见 [reference.md](./reference.md)。

### 请求模式

| 模式 | 典型请求 | 行为 |
| --- | --- | --- |
| `message-only` | “写一个 commit message” | 只返回建议的 message，不修改 Git 状态 |
| `command-only` | “生成提交命令” | 范围明确后返回完整安全命令，不执行 |
| `execute-mode` | “帮我提交 Git” | 核对范围与状态后执行普通 commit |

### 环境要求

| Git 运行环境 | 执行器 | 最低要求 |
| --- | --- | --- |
| Windows | `scripts/commit.ps1` | Windows PowerShell 5.1 或 PowerShell 7、Git |
| WSL / Linux | `scripts/commit.sh` | Bash、Git、`iconv`、`base64` 与常见 POSIX 工具 |
| macOS | `scripts/commit.sh` | 系统 Bash 3.2+、Git、`iconv`、`base64` 与常见 POSIX 工具 |

还需要支持本地技能发现的 Codex 或兼容 Agent 环境。目标仓库的状态检查、测试、临时文件、hooks 和 commit 必须使用同一个 Git 运行环境。

### 安装

下载或克隆本仓库后，将整个 `git-commit-helper` 目录放入 Agent 的技能目录，并保留仓库内的文件结构。实际技能根目录以 Agent 配置为准。

Windows 常见位置：

```text
%USERPROFILE%\.agents\skills\git-commit-helper
```

在 PowerShell 中检查：

```powershell
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"
Test-Path (Join-Path $skillRoot "SKILL.md")
Test-Path (Join-Path $skillRoot "scripts\commit.ps1")
```

WSL/Linux/macOS 常见位置：

```text
$HOME/.agents/skills/git-commit-helper
```

在 Bash 中检查：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
test -f "$skill_root/SKILL.md"
test -f "$skill_root/scripts/commit.sh"
```

每个 WSL 发行版都有独立的 `$HOME`、Git 配置、hooks、凭据和技能发现路径。若要在发行版内直接发现技能，应在该发行版中单独安装；不要把 Windows `%USERPROFILE%` 当成 WSL 的 `$HOME`。

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

技能会先读取仓库状态与改动范围，再通过 index/HEAD 安全视图有界检查测试、调用关系、契约或相关历史，以推断目的和影响。证据支持唯一提交语义时直接继续；仅当多个合理解释会改变 `type`、`subject`、提交范围或影响/风险判断时，才询问一个具体问题。若暂存区为空或路径范围不明确，执行模式会要求先确认范围，不会默认运行 `git add .`。

#### 直接调用脚本

当 commit message 已确定时，在目标仓库所属的 Git 环境中调用对应执行器。

Windows PowerShell：

```powershell
$message = @'
feat(account): 支持用户头像更新

- 用户保存新头像后，后续资料读取返回最新头像
- 覆盖头像更新场景
'@

$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
$messageBase64 = [Convert]::ToBase64String($messageBytes)
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"

& (Join-Path $skillRoot "scripts\commit.ps1") -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
feat(account): 支持用户头像更新

- 用户保存新头像后，后续资料读取返回最新头像
- 覆盖头像更新场景
COMMIT_MESSAGE
```

如果 Codex 在 Windows 中运行、目标仓库由 WSL Git 管理，请使用 [examples.md](./examples.md#windows-控制-wsl-仓库) 中的 bridge 示例：显式选择发行版，用该发行版的 `wslpath` 转换 Windows 侧技能路径，再让 WSL Bash 和 WSL Git 完成整个事务。

两个执行器都以受保护执行早期复制 index 的时点定义 staged 快照；POSIX 执行器会在读取可能阻塞的 message 之前完成复制。只有实际 commit tree 与该快照一致时，才会把提交视为安全完成。message 的内容与提交范围仍应在调用前完成审阅。

### 安全模型

- 不默认执行 `git add .`。只有用户明确指定路径或全部范围时，Agent 工作流才会逐路径暂存并重新检查。
- 当前平台执行器在仓库外创建唯一临时目录，并通过 `GIT_INDEX_FILE` 使用真实 index 的独立快照。
- 在 commit 前以 `git write-tree` 记录预期 tree，并在 commit 后核对实际 tree；若 hook 使两者不一致，执行器会在安全条件满足时受保护地恢复原引用，或在状态不确定时停止并要求人工检查。
- 使用唯一 `GIT_REFLOG_ACTION` 识别本次创建的 commit，并检查 HEAD 是否发生并发移动。
- 只有在目标 commit 可被明确识别且引用状态仍安全时，才可能通过带旧值校验的 `update-ref` 恢复原引用；否则停止并保留现场供人工检查。
- Git 调用使用 `--no-pager`，避免等待交互式分页器。
- 执行器会在结束时尝试清理临时目录；若清理失败，会报告残留路径。若输出包含 `Do not retry commit`，commit 可能已经成功，必须先检查仓库，不能直接重试。
- WSL 场景中，仓库路径、执行器、Git、临时目录与 hooks 保持在同一个发行版；不把 Windows 路径或 Windows 临时 index 交给 WSL Git。

### 目录结构

```text
git-commit-helper/
├── .gitattributes
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── commit.ps1
│   └── commit.sh
└── tests/
    └── test_commit_sh.sh
```

- [.gitattributes](./.gitattributes)：强制 Bash 脚本使用 LF，避免 Windows checkout 破坏 WSL 执行
- [SKILL.md](./SKILL.md)：Agent 执行流程与硬性边界
- [examples.md](./examples.md)：常见 staged、unstaged 与混合状态示例
- [reference.md](./reference.md)：类型、scope、风险与验证参考
- [scripts/commit.ps1](./scripts/commit.ps1)：Windows PowerShell 提交执行器
- [scripts/commit.sh](./scripts/commit.sh)：WSL/Linux/macOS Bash 提交执行器
- [tests/test_commit_sh.sh](./tests/test_commit_sh.sh)：POSIX 执行器的跨环境回归测试

### 能力边界

- 只处理普通 commit，不执行 push、merge、rebase 或 amend。
- 发现冲突，或 merge、rebase、cherry-pick、revert 正在进行时，会停止普通提交流程。
- staged 为空且范围不明确时，需要用户选择路径；不会猜测要提交的文件。
- 默认从证据推断改动意图，不要求用户复述任务；只有多个合理解释会改变提交语义时才请求最小必要信息。
- hooks 可以执行，但如果 hook 改变了预期 tree 或造成状态不确定，当前平台执行器会拒绝把结果当作安全完成。
- 清理失败或 HEAD 状态不明确时，请按错误信息检查仓库；看到 `Do not retry commit` 时不要重复运行。

<a id="english"></a>

## English

### Overview

Git Commit Helper is a cross-platform local skill for Codex and other compatible agents. It reconstructs the purpose and impact of the current changes before generating, reviewing, or executing a well-scoped commit. It analyzes the staging area first, follows the repository's existing commit style, and falls back to Conventional Commits when no clear convention exists.

The skill supports Windows PowerShell, WSL, Linux, and macOS while keeping staged and unstaged changes strictly separated.

### Highlights

- **Staged-first analysis**: The commit message describes only the confirmed scope; intent research uses index/HEAD-safe views so unstaged edits in the same file stay out of the intended commit.
- **Intent-first analysis**: User context, tests, callers, contracts, and relevant history establish why the change exists, how behavior changes, and who is affected instead of merely paraphrasing the diff.
- **Low-interaction inference**: The skill proceeds when evidence supports one commit meaning and asks one minimal question only when competing interpretations would materially change it.
- **Repository-aware style**: Recent commits are preferred as the style guide; otherwise the skill uses `type(scope): subject`.
- **Three request modes**: Generate only a message, generate a safe command without running it, or verify and execute a commit.
- **Two native executors**: Windows uses PowerShell; WSL/Linux/macOS use Bash. Both enforce the same isolated-index, tree, reflog, and concurrency contract.
- **Cross-shell UTF-8 safety**: PowerShell uses Base64, while Bash accepts a quoted heredoc, a message file, or Base64 for multiline and non-ASCII text.
- **WSL runtime isolation**: Inspection, hooks, the temporary index, and commit stay inside one WSL distribution instead of mixing Windows Git with WSL Git.

See [SKILL.md](./SKILL.md) for the complete behavior, [examples.md](./examples.md) for end-to-end scenarios, and [reference.md](./reference.md) for decision rules.

### Request modes

| Mode | Example request | Behavior |
| --- | --- | --- |
| `message-only` | “Write a commit message” | Returns a suggested message without changing Git state |
| `command-only` | “Generate the commit command” | Returns a complete safe command once scope is clear, without running it |
| `execute-mode` | “Commit these changes” | Verifies scope and repository state, then creates an ordinary commit |

### Requirements

| Git environment | Executor | Minimum requirements |
| --- | --- | --- |
| Windows | `scripts/commit.ps1` | Windows PowerShell 5.1 or PowerShell 7, plus Git |
| WSL / Linux | `scripts/commit.sh` | Bash, Git, `iconv`, `base64`, and common POSIX tools |
| macOS | `scripts/commit.sh` | System Bash 3.2+, Git, `iconv`, `base64`, and common POSIX tools |

Codex or another compatible agent environment must also support local skill discovery. Repository inspection, tests, temporary files, hooks, and commit must all use the same Git runtime.

### Installation

Download or clone this repository, then place the entire `git-commit-helper` directory in your agent's skills directory without changing its internal structure. The agent's configured skill root takes precedence over these examples.

Common Windows location:

```text
%USERPROFILE%\.agents\skills\git-commit-helper
```

Verify it in PowerShell:

```powershell
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"
Test-Path (Join-Path $skillRoot "SKILL.md")
Test-Path (Join-Path $skillRoot "scripts\commit.ps1")
```

Common WSL/Linux/macOS location:

```text
$HOME/.agents/skills/git-commit-helper
```

Verify it in Bash:

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
test -f "$skill_root/SKILL.md"
test -f "$skill_root/scripts/commit.sh"
```

Each WSL distribution has its own `$HOME`, Git configuration, hooks, credentials, and skill discovery path. Install the skill in that distribution if the agent should discover it there; a Windows `%USERPROFILE%` directory is not the distribution's `$HOME`.

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

The skill inspects repository state and scope first, then uses index/HEAD-safe views for a bounded review of tests, callers, contracts, or relevant history to infer purpose and impact. It proceeds when the evidence supports one commit meaning and asks a specific question only when competing interpretations would change the type, subject, scope, or impact/risk statement. If nothing is staged or the path scope is ambiguous, execute mode asks for confirmation instead of defaulting to `git add .`.

#### Invoke an executor directly

Once the commit message is final, invoke the executor that belongs to the target repository's Git environment.

Windows PowerShell:

```powershell
$message = @'
feat(account): return updated user avatars

- profile reads return the latest avatar after an account updates it
- cover the avatar update flow
'@

$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
$messageBase64 = [Convert]::ToBase64String($messageBytes)
$skillRoot = Join-Path $HOME ".agents\skills\git-commit-helper"

& (Join-Path $skillRoot "scripts\commit.ps1") -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS:

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
feat(account): return updated user avatars

- profile reads return the latest avatar after an account updates it
- cover the avatar update flow
COMMIT_MESSAGE
```

If Codex runs on Windows while WSL Git owns the target repository, use the bridge in [examples.md](./examples.md#windows-控制-wsl-仓库): select the distribution explicitly, convert the Windows-side skill path with that distribution's `wslpath`, and let WSL Bash and WSL Git perform the whole transaction.

The point where an executor copies the index early in guarded execution defines the staged snapshot; the POSIX executor performs that copy before reading potentially blocking message input. A commit is treated as safely completed only when its tree matches that snapshot. Review the message and intended scope before invoking it.

### Safety model

- It does not default to `git add .`. The agent workflow stages only explicit paths, followed by a fresh review, when the user has clearly selected paths or the complete scope.
- The selected executor creates a unique temporary directory outside the repository and uses `GIT_INDEX_FILE` with an isolated copy of the real index.
- Before committing, `git write-tree` records the expected tree and the resulting commit tree is checked afterward. If a hook makes them differ, the executor performs a guarded ref restore when safe or stops for manual inspection when state is uncertain.
- A unique `GIT_REFLOG_ACTION` identifies the commit created by the invocation, while HEAD movement is checked for concurrent changes.
- A ref can be restored with an old-value-guarded `update-ref` only when the created commit and ref state are unambiguous; otherwise the script stops and preserves the state for inspection.
- Git runs with `--no-pager`, preventing waits on an interactive pager.
- The executor attempts to clean up its temporary directory at the end and reports the retained path if cleanup fails. If output contains `Do not retry commit`, a commit may already exist; inspect the repository before doing anything else.
- In WSL, the repository path, executor, Git process, temporary directory, and hooks stay in the same distribution. Windows paths and Windows temporary indexes are never passed to WSL Git.

### Repository structure

```text
git-commit-helper/
├── .gitattributes
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── commit.ps1
│   └── commit.sh
└── tests/
    └── test_commit_sh.sh
```

- [.gitattributes](./.gitattributes): keeps Bash scripts on LF so Windows checkouts remain runnable in WSL
- [SKILL.md](./SKILL.md): agent workflow and hard boundaries
- [examples.md](./examples.md): common staged, unstaged, and mixed-state examples
- [reference.md](./reference.md): type, scope, risk, and verification guidance
- [scripts/commit.ps1](./scripts/commit.ps1): Windows PowerShell executor
- [scripts/commit.sh](./scripts/commit.sh): WSL/Linux/macOS Bash executor
- [tests/test_commit_sh.sh](./tests/test_commit_sh.sh): cross-environment regression tests for the POSIX executor

### Scope boundaries

- The skill handles ordinary commits only; it does not push, merge, rebase, or amend.
- It stops the ordinary commit flow when conflicts exist or a merge, rebase, cherry-pick, or revert is in progress.
- If the staging area is empty and scope is unclear, the user must select paths; the skill does not guess which files belong in the commit.
- It infers change intent from evidence instead of asking the user to restate the task; it requests minimal information only when multiple reasonable interpretations would change the commit meaning.
- Hooks may run, but if a hook changes the expected tree or leaves repository state uncertain, the selected executor refuses to treat the result as safely completed.
- If cleanup fails or HEAD state is unclear, inspect the repository as instructed by the error. Never rerun the command after a `Do not retry commit` warning.
