---
name: chinese-git-commit-and-push
description: >-
  Inspects git diff and status, generates a detailed and well-structured Chinese commit message,
  stages changes, commits, and pushes to remote repository when explicitly requested by the user.
---

# Chinese Git Commit & Push (中文详细提交与推送)

Use this skill when the user explicitly requests to commit and push changes, generate detailed Chinese commit messages, or commands like `提交并推送`, `生成commit message并push`, `/commit-push`.

---

## 核心工作流程 (Workflow)

```
 [1. 检查状态与代码差异]
      │  (git status / git diff 检查所有暂存与未暂存的修改)
      ▼
 [2. 分析改动并生成结构化中文 Commit Message]
      │  (按照 Type(Scope) + 背景 + 核心改动 + 技术细节 + 验证情况 规范生成)
      ▼
 [3. 暂存改动文件 (git add)]
      │  (精准暂存本次改动的代码、资源与测试文件，过滤不必要的临时文件)
      ▼
 [4. 执行提交 (git commit)]
      │  (将详细中文 Commit Message 写入提交历史)
      ▼
 [5. 推送至远程仓库 (git push)]
      │  (推送到当前分支对应的远程分支并确认推送成功)
      ▼
 [6. 结果汇总与反馈]
      │  (向用户汇报提交哈希、提交信息全文及远程推送状态)
```

---

## 详细执行步骤 (Step-by-Step Instructions)

### 第一步：审查工作区状态与差异
1. 执行 `git status` 查看已修改、未追踪及已暂存的文件列表。
2. 执行 `git diff`（查看未暂存差异）以及 `git diff --cached`（查看已暂存差异）。
3. 检查当前分支名称：`git branch --show-current`。

---

### 第二步：生成详细结构化中文 Commit Message
遵循 **Conventional Commits** 扩展的中文详细说明规范：

```text
<type>(<scope>): <简要总结（动宾短语，不超过 50 字）>

## 变更背景 (Why)
- 简述本次修改的需求背景、目的或解决的问题。

## 主要改动 (What)
- [模块/文件]: 详细列出修改点、新增类/方法或重构逻辑。
- [模块/文件]: 详细列出 UI、资源或配置调整。

## 技术细节 (How & Details)
- 涉及的核心算法、数据流转、边界条件处理或性能去重机制。
- 架构兼容性与设计考量。

## 验证情况 (Verification)
- 自动化测试执行结果及测试用例覆盖列表。
```

#### Commit Type 规范：
- `feat`: 新增特性 / 业务功能
- `fix`: 修复 Bug 或异常行为
- `refactor`: 代码重构（既非修复 Bug 也非新增功能）
- `perf`: 性能提升或资源优化
- `test`: 新增或修改自动化测试
- `docs`: 文档、说明或注释变更
- `chore`: 构建流程、依赖管理或辅助工具配置
- `style`: 代码格式调整（空格、分号等，不影响逻辑）

---

### 第三步：暂存修改文件 (Stage Changes)
1. 明确暂存本次工作涉及的文件：
   ```powershell
   git add <file1> <file2> ...
   ```
2. 如整个工作区均为本次任务改动且无遗漏或冗余临时文件，可使用：
   ```powershell
   git add -A
   ```

---

### 第四步：执行本地提交 (Git Commit)
将格式化中文 Commit Message 传给 `git commit`：
```powershell
git commit -m @"
<type>(<scope>): <简要总结>

## 变更背景
<背景内容>

## 主要改动
<改动列表>

## 技术细节
<技术实现细节>

## 验证情况
<验证结果>
"@
```

---

### 第五步：推送到远程仓库 (Git Push)
1. 推送当前分支到远端：
   ```powershell
   git push origin <current_branch>
   ```
   若当前分支未设置上游跟踪分支：
   ```powershell
   git push -u origin <current_branch>
   ```
2. 确认 push 返回值为 0 且无远程冲突。

---

### 第六步：输出反馈
向用户展示：
- 提交的 **Commit SHA**
- 目标 **分支名称**
- 最终提交的 **Commit Message 全文**
- 远程仓库 **Push 状态**
