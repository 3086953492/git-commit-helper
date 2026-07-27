---
name: git-commit-helper
description: Use when 用户要求基于 Git 改动推断改动意图与影响，或生成、审阅、执行 Conventional Commit，包括“提交git”“帮我提交”“生成提交命令”“写 commit message”，以及需要在 Windows PowerShell、WSL、Linux、macOS 中处理 staged/unstaged 边界的场景。
---

# Git Commit Helper

基于实际 Git 改动还原“为什么改、行为如何变化、会影响谁”，再生成或执行范围清晰、可验证的提交。默认保护现有 staged 边界，不把 unstaged 或 untracked 内容混入提交。

## 核心约束

- 先确定仓库根目录、分支和 staged 范围，再生成 message。
- staged 非空时以 index 为提交与证据边界；可只读检查相关上下文，但不得把 unstaged 或 untracked 内容算入提交。
- staged 为空时，仅在只读模式分析 unstaged/untracked；执行模式不得默认 `git add .`。
- diff 只定义提交边界，不等于改动意图。生成 message 前必须结合用户上下文、测试、调用关系、契约或相关历史，还原目的与影响。
- 默认自行推断并继续，不要求用户确认推断结果。只有多个合理解释会实质改变 `type`、`subject`、提交范围或影响/风险表述时，才询问一个最小必要问题。
- 优先遵循仓库已有 commit 规范；没有明确规范时再使用本技能的中文 Conventional Commit 默认值。
- 生成命令时使用当前 shell 的无插值多行语法：PowerShell 使用单引号 here-string，Bash 使用带单引号的 heredoc delimiter。
- 检查、暂存、验证、临时 index、hooks 和 commit 必须全部使用目标仓库所属的同一个 Git 运行环境；不得混用 Windows Git 与 WSL Git。
- 本技能只处理普通 commit，不执行 push、merge、rebase 或 amend；这些操作必须切换到对应工作流单独处理。

## 请求模式与动作（request-contract）

| 模式 | 常见请求 | 动作 |
|---|---|---|
| `message-only` | “写 commit message”“这批改动怎么描述” | 只输出建议 message，不修改 Git 状态 |
| `command-only` | “生成提交命令”“给我可执行命令” | 范围明确后输出完整安全命令，不执行 |
| `execute-mode` | “提交git”“帮我提交”“生成并提交” | staged 范围和提交语义清晰时验证并直接提交；仅在范围不清或多个解释会改变提交语义时询问最小必要信息 |

用户要求“看看”“审阅”或“建议”时，不得执行提交。用户明确要求提交且 staged 范围已经准备好时，不要重复请求范围确认或意图确认；先按下文证据链自行判断。

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

- staged 非空：读取完整 `git diff --cached`，以 index 内容定义提交范围；上下文只用于解释，不能把 unstaged 或 untracked 内容写进 message。
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

### 3. 还原改动意图与影响

在生成 message 前，为每个连贯的 staged 主题形成一份内部“意图简报”：

```text
目标：这批改动要解决什么问题或实现什么结果
行为变化：改动前 → 改动后
影响：受影响的用户、调用路径、接口、数据或运行特征
边界：兼容性、风险与明确未改变的行为
证据：支撑判断的用户上下文、测试、调用关系、契约或历史
```

staged 非空时，调查必须使用 index/HEAD 安全视图：

- 用 `git show :<path>` 读取文件的 staged 完整版本，用 `git show HEAD:<path>` 对照改动前版本。
- 用 `git grep --cached -n <symbol>` 在 index 中查找调用方与契约；不要用工作区 `rg` 结果直接支撑 staged message。
- 未 staged 的 tracked 路径默认读取 `HEAD` 版本；只有 `git status --short -- <path>` 证明路径干净时，工作区内容才等同于 index。
- unstaged 或 untracked 内容可以提示“当前 staged 可能不完整”，但不能证明本次提交的目的、行为或影响。

按以下顺序做有界调查；一旦 index 与上下文证据已支持唯一且连贯的解释就停止：

1. 当前用户请求、已批准方案、问题描述或任务上下文。
2. staged 中变化的测试、断言、注释、文档、配置和迁移。
3. 变更符号的上下文、直接调用方、API/UI 契约、数据读写路径。
4. 仍有歧义时，检查相关路径的近期提交、`git log -S` 或 `git blame`；不要浏览无关历史。
5. 用 staged diff 核对实现是否完整支撑该意图，不把上下文里尚未进入 staged 的计划写进 message。

影响判断只写证据支持的维度，例如用户行为、API、数据、兼容性、安全、性能或运维。测试文件说明“如何证明”，不能自动充当改动目的。

交互门槛：

- 有一个明显最合理的解释：直接继续，即使该解释来自代码证据而非用户明说。
- 商业动机未知，但行为结果唯一：使用保守、结果导向的表述继续；不虚构“提升体验”“增强安全”等价值。
- 有多个解释，但它们不会改变提交语义：选择共同且可证明的结果继续，不询问。
- 有多个合理解释，并会改变 `type`、`subject`、提交边界或影响/风险表述：只问一个能区分这些解释的具体问题；不要泛问“这次改动意图是什么？”。
- 无法把 staged 内容归为一个连贯目的：停止执行并建议拆分。不要自动重建或部分取消用户的 index；等待用户准备一个连贯 staged 子集，然后重新运行全部 staged 检查与意图分析。

### 4. 生成提交信息

默认格式：

```text
<type>(<scope>): <目的或可观察结果>

- <受影响对象或条件>：<可观察行为及主要影响>
- <必要的接口、兼容或验证证据>
- 被动更新
```

- `type` 按改动目的和外部行为判定，不按文件类型或代码动作判定。
- 只有配置值、常量或默认值变化，且没有新能力或缺陷修复证据时，遵循仓库惯例；无稳定惯例时使用 `chore`，不要猜成 `feat` 或 `fix`。
- `scope` 仅在有明确业务域时使用。
- `subject` 优先概括目的或可观察结果，避免复述“修改字段”“更新配置”“调整逻辑”。
- 正文第一条必须点明受影响对象或生效条件，以及它将观察到的行为；“把 X 从 A 改为 B”本身不算影响说明。
- 若没有外部行为变化，正文第一条写内部目标及保持不变的外部契约；不要虚构用户价值。
- 正文 bullet 之间不插入空行。
- 不把锁文件、生成文件或依赖文件误判为主体。
- 不写意图简报无法证明的收益；实现细节只在解释影响或验证时出现。
- message 必须只描述当前明确的分析范围；`execute-mode` 中该范围必须等于最终 staged patch。

输出前逐项检查 message：

1. 只看 `subject`，能否知道目的或结果，而不只是看到代码动作？
2. 只看正文第一条，能否知道谁或什么条件下的行为发生变化？
3. 删除文件名、函数名和字段名后，目的与影响是否仍然成立？

任一答案为否，返回意图简报重新生成，不得提交。

### 5. 执行前验证

在 `execute-mode` 中：

1. 确认 `git diff --cached --check` 通过。
2. 根据意图简报中的行为与影响面，运行最小但充分的测试、构建或静态检查。
3. 再次读取 `git diff --cached --stat`、`--name-status` 和完整 staged diff。
4. 确认最终 staged patch 仍支持同一意图；若验证会改动文件，确认这些变化没有被意外加入 staged。

### 6. 安全执行

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
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)
& "<skill-root>\scripts\commit.ps1" -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
COMMIT_MESSAGE
```

从 Windows 调用 WSL 时，使用 [examples.md](examples.md) 中的 Base64 bridge 示例，显式指定发行版并让 WSL Git 完成整个事务。

`command-only` 只输出命令；`execute-mode` 才实际运行。

## 常见错误

- 只把 diff 改写成自然语言：先形成“目标、行为变化、影响、证据”，再写 message。
- 看到配置数值变化就编造收益：动机无证据时，写唯一可证明的行为结果与影响。
- 一开始就问用户“为什么改”：先调查测试、调用方、契约和相关历史；只有多个语义不同的解释仍并存时才问。
- 把“用户没有亲口确认”当成歧义：能由证据得到唯一合理解释时直接继续。
- 因为控制端是 Windows 就调用 `commit.ps1`：应按目标仓库的 Git 运行环境选择执行器。
- 默认使用 WSL 默认发行版或硬编码 `/mnt/c`：应显式确定发行版，并在其中用 `wslpath` 转换 Windows 路径。
- 用一套 Git 检查 staged、再用另一套 Git commit：应让检查、验证、hooks 和 commit 留在同一运行环境。
- POSIX 执行器不可用时退化为裸 `git commit`：应停止并报告缺失的 Bash/Git/工具依赖。

## 输出要求

始终说明：

- 提交模式和范围。
- 经证据归纳的改动意图与主要影响；保持简洁，不必展示完整内部简报。
- Git 运行环境与选定执行器。
- commit message。
- 已运行或建议运行的验证。
- `command-only` 的完整命令，或 `execute-mode` 的最终 hash/message 和剩余状态。

提交后不要只依据 `git commit` 文本判断成功；必须以脚本回读的 hash/message 和最终 status 为准。

## 按需资料

- message 判定规则：[reference.md](reference.md)
- 三种模式与 Windows→WSL bridge 示例：[examples.md](examples.md)
