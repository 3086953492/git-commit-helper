# Git Commit Helper

[中文](#中文) | [English](#english)

<a id="中文"></a>

## 中文

### 简介

Git Commit Helper 是一个面向 Codex 与其他兼容 Agent 的跨平台本地技能，根据 Git 改动与已有上下文生成或审阅简洁的提交消息。用户明确要求时，也可提供提交命令或执行普通 commit。它优先使用暂存区范围，引导目标仓库接入 commitlint，由实际配置约束消息结构。

本技能支持 Windows PowerShell、WSL、Linux 与 macOS，并在所有受支持环境中严格隔离 staged 与 unstaged 改动。

### 功能亮点

- **暂存区优先**：提交说明只描述已确认的改动范围；意图调查使用 index/HEAD 安全视图，同一文件中的未暂存改动不会混入目标 commit。
- **按需读取**：复用已有上下文和未变化的 diff，信息不足时才补读相关内容；不固定调查调用链、历史或生成意图简报。
- **消息校验**：生成完成后调用目标仓库本地 commitlint，实际提交再由 `commit-msg` hook 拦截；不承担测试、构建、代码 lint 或代码审查。
- **按需接入**：目标仓库没有 commitlint 时首次引导，用户可跳过；同一会话不重复询问已拒绝的接入。
- **遵循仓库规则**：以实际生效的 commitlint 配置为结构规则来源，保留准确、简洁的消息内容要求。
- **三种请求模式**：可只生成 message、只生成安全命令，或按明确请求执行 commit。
- **双原生执行器**：Windows 使用 PowerShell，WSL/Linux/macOS 使用 Bash；两者共享独立 index 快照、tree 校验、reflog 标记和并发保护。
- **跨 shell UTF-8 安全**：PowerShell 通过 Base64，Bash 通过 quoted heredoc、message 文件或 Base64 安全传递多行与非 ASCII message。
- **WSL 环境隔离**：检查、hooks、临时 index 和 commit 始终在同一个 WSL 发行版内完成，不混用 Windows Git。

更多行为细节见 [SKILL.md](./SKILL.md)，完整场景见 [examples.md](./examples.md)，判断规则见 [reference.md](./reference.md)。

### 请求模式

| 模式 | 典型请求 | 行为 |
| --- | --- | --- |
| `message-only` | “写一个 commit message” | 校验后返回建议的 message，不暂存或提交 |
| `command-only` | “生成提交命令” | 校验消息后返回完整安全命令，不执行暂存或提交 |
| `execute-mode` | “帮我提交 Git” | 范围明确后调用脚本执行普通 commit |

### 环境要求

| Git 运行环境 | 执行器 | 最低要求 |
| --- | --- | --- |
| Windows | `scripts/commit.ps1` | Windows PowerShell 5.1 或 PowerShell 7、Git |
| WSL / Linux | `scripts/commit.sh` | Bash、Git、`iconv`、`base64` 与常见 POSIX 工具 |
| macOS | `scripts/commit.sh` | 系统 Bash 3.2+、Git、`iconv`、`base64` 与常见 POSIX 工具 |

还需要支持本地技能发现的 Codex 或兼容 Agent 环境。读取、暂存、临时文件、hooks 和 commit 使用目标仓库所属的同一个 Git 运行环境。

目标仓库接入 commitlint 后，还需要与其依赖版本兼容的 Node.js 和包管理器。非 Node 仓库会先说明新增开发工具链；用户可跳过接入并获得未经校验的消息。安装和使用技能本身不需要安装本仓库的 npm 开发依赖；维护本仓库时见下方说明。

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
使用 $git-commit-helper，提交当前 staged 改动。
```

已有 diff 或待润色消息足够时直接复用，不重复读取改动。目标仓库明确时，首次检查 commitlint 接入情况，之后复用已知结果；三种模式都会在返回最终消息、命令或执行提交前校验候选消息。缺少配置时先引导接入，用户可跳过；没有目标仓库的纯文本请求不强制接入，并注明未经校验。具体步骤见 [commitlint 接入与校验](./references/commitlint.md)。

需要读取本地改动时，仅补充缺少的信息；不例行执行 stat、name-status、check 或反复通读 diff。范围与结果清楚时直接继续。暂存区为空时沿用用户已指定的路径或全部范围；没有范围授权时才请求选择，不默认运行 `git add .`。同意接入 commitlint 不会自动暂存新增配置。

本技能只承担消息校验，不承担代码验收。用户另外要求的验证和仓库明确规定的要求独立处理，不因调用本技能而重跑；已有规则和 hooks 保留。脚本的 Git 事务保护和提交结果回读仍然保留，Agent 无需在调用前后重复这些步骤。

#### 直接调用脚本

当 commit message 已确定并按目标仓库规则完成前置校验时，在目标仓库所属的 Git 环境中调用对应执行器。直接调用脚本只执行已有 hooks，不负责安装 commitlint 或单独执行前置校验。

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

### 维护本仓库

使用 Node.js 22.12.0+ 与 npm，在仓库根目录安装开发依赖：

```sh
npm ci
```

安装时 `prepare` 会配置 Husky，之后普通提交和本仓库的提交执行器都会通过 `commit-msg` hook 调用 commitlint。规则继承 `@commitlint/config-conventional`，关闭描述大小写限制，以支持中文及 Git、WSL 等技术名词。实际规则见 [commitlint.config.cjs](./commitlint.config.cjs)。

手动检查消息文件或提交范围：

```sh
npm run commitlint -- --edit path/to/message.txt
npm run commitlint -- --from HEAD~1 --to HEAD --verbose
```

如果需要重新安装本地 hook，运行 `npm run prepare`。Windows 与 WSL 分别在各自的 Node.js/Git 环境中安装依赖。

### 安全模型

- 不默认执行 `git add .`。沿用用户已明确指定的路径或全部范围，使用显式路径暂存；同样的内容不因暂存再读一遍。
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
├── .gitignore
├── .husky/
│   └── commit-msg
├── commitlint.config.cjs
├── package.json
├── package-lock.json
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── references/
│   └── commitlint.md
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── commit.ps1
│   └── commit.sh
└── tests/
    └── test_commit_sh.sh
```

- [.gitattributes](./.gitattributes)：强制 Bash 脚本使用 LF，避免 Windows checkout 破坏 WSL 执行
- [SKILL.md](./SKILL.md)：消息生成、按需读取与请求模式
- [examples.md](./examples.md)：常见 staged、unstaged 与混合状态示例
- [reference.md](./reference.md)：消息类型与措辞示例
- [references/commitlint.md](./references/commitlint.md)：目标仓库的工具接入、前置校验与 hook 兼容
- [scripts/commit.ps1](./scripts/commit.ps1)：Windows PowerShell 提交执行器
- [scripts/commit.sh](./scripts/commit.sh)：WSL/Linux/macOS Bash 提交执行器
- [tests/test_commit_sh.sh](./tests/test_commit_sh.sh)：POSIX 执行器的跨环境回归测试

### 能力边界

- 只处理普通 commit，不执行 push、merge、rebase 或 amend。
- 发现冲突，或 merge、rebase、cherry-pick、revert 正在进行时，会停止普通提交流程。
- staged 为空且范围不明确时，需要用户选择路径；不会猜测要提交的文件。
- 根据已有证据写消息，不要求用户复述任务；多个主题可建议拆分，但尊重用户明确要求一起提交的选择。
- hooks 可以执行，但如果 hook 改变了预期 tree 或造成状态不确定，当前平台执行器会拒绝把结果当作安全完成。
- 清理失败或 HEAD 状态不明确时，请按错误信息检查仓库；看到 `Do not retry commit` 时不要重复运行。

<a id="english"></a>

## English

### Overview

Git Commit Helper is a cross-platform local skill for Codex and other compatible agents. It generates or reviews concise commit messages from Git changes and existing context. It provides commands or executes ordinary commits only when explicitly requested. It prefers the staged scope and guides target repositories through commitlint setup so their effective configuration controls message structure.

The skill supports Windows PowerShell, WSL, Linux, and macOS while keeping staged and unstaged changes strictly separated.

### Highlights

- **Staged-first analysis**: The commit message describes only the confirmed scope; intent research uses index/HEAD-safe views so unstaged edits in the same file stay out of the intended commit.
- **On-demand reading**: Reuses existing context and unchanged diffs, reading related content only when needed; no routine caller/history investigation or fixed intent brief.
- **Message validation**: Runs the target repository's local commitlint before returning a final message or command or executing a commit; the `commit-msg` hook checks again during commits. Does not own tests, builds, code lint, or code reviews.
- **Optional onboarding**: Offers commitlint setup when missing. Users may skip, without repeated prompts in the same conversation.
- **Repository rules**: Uses effective commitlint configuration for message structure while retaining accurate, concise content.
- **Three request modes**: Generate only a message, generate a safe command without running it, or execute a commit when explicitly requested.
- **Two native executors**: Windows uses PowerShell; WSL/Linux/macOS use Bash. Both enforce the same isolated-index, tree, reflog, and concurrency contract.
- **Cross-shell UTF-8 safety**: PowerShell uses Base64, while Bash accepts a quoted heredoc, a message file, or Base64 for multiline and non-ASCII text.
- **WSL runtime isolation**: Inspection, hooks, the temporary index, and commit stay inside one WSL distribution instead of mixing Windows Git with WSL Git.

See [SKILL.md](./SKILL.md) for the complete behavior, [examples.md](./examples.md) for end-to-end scenarios, and [reference.md](./reference.md) for decision rules.

### Request modes

| Mode | Example request | Behavior |
| --- | --- | --- |
| `message-only` | “Write a commit message” | Validates and returns a suggested message without staging or committing |
| `command-only` | “Generate the commit command” | Validates the message and returns a safe command without staging or committing |
| `execute-mode` | “Commit these changes” | Calls the executor to create an ordinary commit once scope is clear |

### Requirements

| Git environment | Executor | Minimum requirements |
| --- | --- | --- |
| Windows | `scripts/commit.ps1` | Windows PowerShell 5.1 or PowerShell 7, plus Git |
| WSL / Linux | `scripts/commit.sh` | Bash, Git, `iconv`, `base64`, and common POSIX tools |
| macOS | `scripts/commit.sh` | System Bash 3.2+, Git, `iconv`, `base64`, and common POSIX tools |

Codex or another compatible agent environment must also support local skill discovery. Reading, staging, temporary files, hooks, and commit use the target repository's Git runtime.

Targets using commitlint also need Node.js and a package manager compatible with their dependencies. For non-Node repositories, onboarding explains the added development toolchain first. Users may skip setup and receive unvalidated messages. Installing or using the skill does not require this repository's npm development dependencies; contributors should follow the maintenance instructions below.

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
Use $git-commit-helper to commit the currently staged changes.
```

When a supplied diff or message is sufficient, the skill reuses it without rereading changes. For an identified target repository, it checks commitlint setup once and reuses that information. All three modes validate the final candidate before returning a message or command or executing a commit. Missing configuration triggers optional onboarding. Text-only requests without a target repository remain available, with an unvalidated notice. See [commitlint setup and validation](./references/commitlint.md).

When local changes must be read, the skill obtains only missing information, with no routine stat/name-status/check commands or repeated full diff reads. With an empty staging area, it uses paths or the complete scope already selected by the user; otherwise it asks for scope instead of defaulting to `git add .`. Approving commitlint setup does not automatically stage its configuration files.

The skill owns message validation, not code acceptance. Separately requested verification and explicit repository requirements remain separate work and are not rerun merely because this skill is invoked. Existing rules and hook behavior are preserved. The scripts retain Git transaction protection and result readback, which the agent does not duplicate before or after invocation.

#### Invoke an executor directly

Once the commit message is final and has passed the target repository's validation, invoke the executor that belongs to its Git environment. Direct executor calls run existing hooks but do not install commitlint or perform a separate preliminary message check.

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

### Maintaining this repository

Use Node.js 22.12.0+ and npm to install development dependencies from the repository root:

```sh
npm ci
```

The `prepare` script configures Husky during installation. Ordinary commits and this repository's commit executors then run commitlint through the `commit-msg` hook. Rules extend `@commitlint/config-conventional`, with subject case unrestricted to support Chinese and technical names such as Git and WSL. See [commitlint.config.cjs](./commitlint.config.cjs) for the actual configuration.

To check a message file or commit range manually:

```sh
npm run commitlint -- --edit path/to/message.txt
npm run commitlint -- --from HEAD~1 --to HEAD --verbose
```

Run `npm run prepare` to reinstall local hooks when needed. Install dependencies separately in the respective Node.js/Git environments when working across Windows and WSL.

### Safety model

- It does not default to `git add .`. It stages explicit paths within the user's already selected scope, without rereading identical content merely because it was staged.
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
├── .gitignore
├── .husky/
│   └── commit-msg
├── commitlint.config.cjs
├── package.json
├── package-lock.json
├── README.md
├── SKILL.md
├── examples.md
├── reference.md
├── references/
│   └── commitlint.md
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── commit.ps1
│   └── commit.sh
└── tests/
    └── test_commit_sh.sh
```

- [.gitattributes](./.gitattributes): keeps Bash scripts on LF so Windows checkouts remain runnable in WSL
- [SKILL.md](./SKILL.md): message generation, on-demand reading, and request modes
- [examples.md](./examples.md): common staged, unstaged, and mixed-state examples
- [reference.md](./reference.md): message types and wording examples
- [references/commitlint.md](./references/commitlint.md): target repository setup, preliminary message validation, and hook compatibility
- [scripts/commit.ps1](./scripts/commit.ps1): Windows PowerShell executor
- [scripts/commit.sh](./scripts/commit.sh): WSL/Linux/macOS Bash executor
- [tests/test_commit_sh.sh](./tests/test_commit_sh.sh): cross-environment regression tests for the POSIX executor

### Scope boundaries

- The skill handles ordinary commits only; it does not push, merge, rebase, or amend.
- It stops the ordinary commit flow when conflicts exist or a merge, rebase, cherry-pick, or revert is in progress.
- If the staging area is empty and scope is unclear, the user must select paths; the skill does not guess which files belong in the commit.
- It writes messages from existing evidence instead of asking the user to restate the task; it may suggest splitting multiple topics but respects an explicit request to commit them together.
- Hooks may run, but if a hook changes the expected tree or leaves repository state uncertain, the selected executor refuses to treat the result as safely completed.
- If cleanup fails or HEAD state is unclear, inspect the repository as instructed by the error. Never rerun the command after a `Do not retry commit` warning.
