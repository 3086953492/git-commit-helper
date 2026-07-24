---
name: git-commit-helper
description: Use when 用户要求基于 Git 改动生成、审阅或执行 Conventional Commit，包括“提交git”“帮我提交”“生成提交命令”“写 commit message”，或需要在 Windows PowerShell、WSL、Linux、macOS 中严格隔离 staged/unstaged 改动并安全处理多行 UTF-8 提交信息。
---

# Git Commit Helper

基于实际 Git 改动生成或执行范围清晰、可验证的提交。默认保护现有 staged 边界，不把 unstaged 或 untracked 内容混入提交。

## 核心约束

- 先确定仓库根目录、分支和 staged 范围，再生成 message。
- staged 非空时只分析 `git diff --cached`；不得把同文件的 unstaged 部分算入提交。
- staged 为空时，仅在只读模式分析 unstaged/untracked；执行模式不得默认 `git add .`。
- 优先遵循仓库已有 commit 规范；没有明确规范时再使用本技能的中文 Conventional Commit 默认值。
- 生成命令时使用当前 shell 的无插值多行语法：PowerShell 使用单引号 here-string，Bash 使用带单引号的 heredoc delimiter。
- 检查、暂存、验证、临时 index、hooks 和 commit 必须全部使用目标仓库所属的同一个 Git 运行环境；不得混用 Windows Git 与 WSL Git。
- 本技能只处理普通 commit，不执行 push、merge、rebase 或 amend；这些操作必须切换到对应工作流单独处理。

## 用户意图与动作（intent-contract）

| 模式 | 常见请求 | 动作 |
|---|---|---|
| `message-only` | “写 commit message”“这批改动怎么描述” | 只输出建议 message，不修改 Git 状态 |
| `command-only` | “生成提交命令”“给我可执行命令” | 范围明确后输出完整安全命令，不执行 |
| `execute-mode` | “提交git”“帮我提交”“生成并提交” | staged 范围清晰时验证并直接提交；只有范围不清时才询问 |

用户要求“看看”“审阅”或“建议”时，不得执行提交。用户明确要求提交且 staged 范围已经准备好时，不要重复请求确认。

## 运行环境与执行器

按目标仓库实际使用的 Git 运行环境选择执行器，而不是按控制端所在系统选择：

| Git 运行环境 | 执行器 |
|---|---|
| Windows Git + Windows 路径 | [scripts/commit.ps1](scripts/commit.ps1) |
| WSL Git、Linux Git 或 macOS Git | `bash` + [scripts/commit.sh](scripts/commit.sh) |

- 已在 WSL/Linux/macOS 内时，直接在该环境运行 `commit.sh`。
- 从 Windows 控制 WSL 仓库时，先确定具体发行版，再通过 `wsl.exe --distribution <Distro> -- ...` 在该发行版内运行 Bash 执行器；仓库路径、脚本路径、临时目录和 Git 都必须是该发行版可见的 POSIX 路径。
- 不硬编码 `/mnt/c`。Windows 路径需要给 WSL 使用时，在目标发行版中调用 `wslpath` 转换。
- 多个 WSL 发行版且目标发行版不明确时，先询问；不得默认选择一个发行版。
- 当前环境不能运行所需执行器时停止并说明阻塞，不得退化为裸 `git commit` 冒充安全流程。

## 工作流

### 1. 定位仓库并读取范围

先运行：

```text
git rev-parse --show-toplevel
git status --short --branch
git diff --cached --stat
git diff --cached --name-status
git diff --cached --check
```

按以下条件处理：

- staged 非空：读取完整 `git diff --cached`，只处理 staged 内容。
- staged 为空且为 `message-only`：读取 `git diff`，再从 `git status --short` 识别 untracked 文件；明确说明本次建议基于哪些未暂存路径。
- staged 为空且为 `command-only`：用户已指定路径时，输出包含显式 `git add -- <paths>`、全部 staged 复检和安全脚本的完整命令；路径未明确时先列出候选文件并请求选择，不输出必然失败的提交命令。
- staged 为空且为 `execute-mode`：列出候选路径并请求用户确认范围。用户已明确指定路径或“全部改动”时，逐路径检查并显式 `git add -- <paths>`，然后重新运行全部 staged 检查。
- 存在冲突、merge/rebase/cherry-pick/revert 进行中或 staged diff 为空：停止普通提交流程并说明原因。

### 2. 识别仓库提交风格

检查 `CONTRIBUTING*`、commitlint 配置和最近提交：

```text
git log -n 20 --pretty=format:%s
```

仓库规范优先于本技能默认值。需要默认规则时，读取 [reference.md](reference.md)。

### 3. 生成提交信息

默认格式：

```text
<type>(<scope>): <subject>

- 核心变更
- 辅助适配
- 被动更新
```

- `scope` 仅在有明确业务域时使用。
- 正文 bullet 之间不插入空行。
- 不把锁文件、生成文件或依赖文件误判为主体。
- message 必须只描述当前明确的分析范围；`execute-mode` 中该范围必须等于最终 staged patch。

### 4. 执行前验证

在 `execute-mode` 中：

1. 确认 `git diff --cached --check` 通过。
2. 根据 staged 文件运行最小但充分的测试、构建或静态检查。
3. 再次读取 `git diff --cached --stat`、`--name-status` 和完整 staged diff。
4. 若验证会改动文件，确认这些变化没有被意外加入 staged。

### 5. 安全执行

使用上表选定的执行器提交。Windows 执行器接收 Base64 编码的 UTF-8 message；POSIX 执行器接收无插值 stdin、message 文件或 Base64。两者都以受保护执行早期复制 index 的时点定义 staged 快照；POSIX 执行器会在读取 message 前完成复制。它们负责：

- 拒绝空 staged、冲突和进行中的 Git 操作。
- 再次运行 `git diff --cached --check`。
- 在仓库外创建唯一临时目录，用 `GIT_INDEX_FILE` 隔离捕获点的 staged 快照；真实 index 不交给 hook 修改。
- 记录快照的 `git write-tree` 结果，并用唯一 reflog action 识别本次 commit；只有该 commit 仍是 HEAD、父关系严格匹配且 symbolic HEAD 仍指向原分支时，才可对捕获的原分支 ref 做 CAS 撤回。
- 若 post-commit hook 或并发进程再次推进 HEAD，不自动改写任何引用；报告本次 commit 与当前 HEAD，并明确提示不得重试。
- 若 HEAD 在相同 commit 上切换到另一分支，或当前为 detached HEAD，也不自动回滚。
- 使用 UTF-8 无 BOM 的临时 message 文件，且不写入仓库或 `.git`。
- 检查 `git commit` 的退出码和 HEAD 是否真实变化。
- 所有非交互 Git 调用都显式使用 `--no-pager`，不继承可能阻塞的分页器配置。
- 成功后输出 `git log -1 --pretty=format:%H%n%B` 与 `git status --short --branch`。
- 无论成功失败都尝试清理临时目录；清理失败时明确报告路径，并在提交已经成功时提示不得重试 commit。

Windows PowerShell：

```powershell
$message = @'
fix(订单状态): 统一状态值格式

- 规范化订单状态并保持 staged 范围不变
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)
& "<skill-root>\scripts\commit.ps1" -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
fix(订单状态): 统一状态值格式

- 规范化订单状态并保持 staged 范围不变
COMMIT_MESSAGE
```

从 Windows 调用 WSL 时，使用 [examples.md](examples.md) 中的 Base64 bridge 示例，显式指定发行版并让 WSL Git 完成整个事务。

`command-only` 只输出命令；`execute-mode` 才实际运行。

## 常见错误

- 因为控制端是 Windows 就调用 `commit.ps1`：应按目标仓库的 Git 运行环境选择执行器。
- 默认使用 WSL 默认发行版或硬编码 `/mnt/c`：应显式确定发行版，并在其中用 `wslpath` 转换 Windows 路径。
- 用一套 Git 检查 staged、再用另一套 Git commit：应让检查、验证、hooks 和 commit 留在同一运行环境。
- POSIX 执行器不可用时退化为裸 `git commit`：应停止并报告缺失的 Bash/Git/工具依赖。

## 输出要求

始终说明：

- 提交模式和范围。
- Git 运行环境与选定执行器。
- commit message。
- 已运行或建议运行的验证。
- `command-only` 的完整命令，或 `execute-mode` 的最终 hash/message 和剩余状态。

提交后不要只依据 `git commit` 文本判断成功；必须以脚本回读的 hash/message 和最终 status 为准。

## 按需资料

- message 判定规则：[reference.md](reference.md)
- 三种模式与 Windows→WSL bridge 示例：[examples.md](examples.md)
