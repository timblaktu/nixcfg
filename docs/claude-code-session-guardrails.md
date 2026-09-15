# Working with the Claude Code session guardrails

This machine's Claude Code accounts come with a small set of built-in guardrails. They exist to turn a handful of "please always remember to..." rules into things the tools simply will not let you do by accident. When a guardrail trips, Claude stops before running the risky command and tells you why, so nothing dangerous happens silently.

You do not have to configure anything to get them. They are on by default for every account on this machine. This guide explains what they do from your point of view, what to do when one blocks you, and how to turn one off if it gets in your way.

## The idea in one paragraph

A few of our working conventions are important enough that a gentle reminder in a config file is not good enough. "Never commit on main", "never leak an AI-attribution trailer into a public repo", "never dump a password into the chat" are the kind of rule where a single slip has a real cost. Each of these is now a guardrail: before Claude runs a matching command, a check looks at what is about to happen and blocks it if it violates the rule. The block is not a punishment. It is a message back to Claude explaining what was wrong and what to do instead, so the work continues correctly.

## When you hit a block

A blocked action looks like a short message beginning with a category name (for example `gitSafety:` or `secretSafety:`) explaining what was refused and how to proceed. Claude will normally read that message and correct course on its own (switch to a feature branch, re-run a command with the right flag, pipe a secret instead of printing it).

You have two escape hatches, and both are set when you launch `claude`, not in the middle of a session:

- **`CLAUDE_HOOKS_BYPASS=1`** turns off every guardrail for that session. Use it when you genuinely need to do the thing a rule normally prevents (for example, landing a merge commit on `main`). Launch with `CLAUDE_HOOKS_BYPASS=1 claude`.
- **`CLAUDE_TASK_SIGNOFF=1`** is specific to the plan-workflow guardrail below. It attests that you (the human) have reviewed the work and are signing off on marking a plan task complete. Launch with `CLAUDE_TASK_SIGNOFF=1 claude`.

These have to be set at launch because the guardrails inherit the environment Claude started with. Exporting a variable from inside a session (in a shell command Claude runs for you) will not reach them. If you realize mid-session that you need a bypass, end the session and relaunch with the variable set.

Every rule is also individually switchable in your Home Manager config (see "Turning a rule off" at the end), so if a guardrail is wrong for how you work, you can disable just that one permanently rather than bypassing everything each session.

## The four categories, in plain terms

### Git safety (`gitSafety`)

Keeps common git mistakes from reaching a remote.

- **Won't skip pre-commit / pre-push checks** (`gitSafety.blockNoVerify`). A `git commit --no-verify` or `git push --no-verify` (and the `-n` short form on commit) is refused, so the checks that are supposed to run before code lands actually run.
- **Won't leak AI attribution into a commit** (`gitSafety.blockAttribution`). A commit message containing an attribution signature - a `Co-Authored-By:` trailer, "Generated with Claude Code", a `claude.ai` link, the Anthropic noreply address, or the robot emoji - is refused. Commits must read as solely human-authored. Note this matches only those leak signatures; simply mentioning "Claude" or "Anthropic" in a message is fine.
- **Won't commit or push on `main`/`master`** (`gitSafety.blockCommitOnMain`). Do your work on a feature branch. This is the guardrail with the widest reach - it applies to every repository on the machine - so a scratch repo where committing straight to `main` is fine is a good candidate for a launch-time bypass.
- **Won't force-add ignored files** (`gitSafety.blockAddForce`). A `git add -f` is refused so `.gitignore` is respected.

### Bash safety (`bashSafety`)

- **Won't run a bare `rm`, `cp`, or `mv`** (`bashSafety.blockBareRm`). Your interactive shell aliases these to their `-i` ("ask me first") form. In the non-interactive shell the tools use, that prompt never gets answered and the command hangs forever. The fix is to run the command with `-f`; the guardrail tells Claude to do exactly that. It deliberately does not silently rewrite your command (a past auto-rewrite experiment corrupted output, so we never rewrite - we block and explain). Related forms with a different leading word, like `rmdir`, `git rm`, or `sudo rm`, are not affected.

### Secret safety (`secretSafety`)

Stops a password or token from ending up in the chat transcript, where it would be stored and searchable.

- **Won't dump the vault into the chat** (`secretSafety.blockVaultDump`). `rbw --full` (which prints every field of an entry, including free-text notes) is always refused. A plain `rbw get` or `rbw code` is refused only when its output would be printed to the screen or written to a file. The safe, intended forms still work: pipe the secret straight to the tool that needs it (`rbw get NAME | some-tool --password-stdin`) or capture it in a variable (`$(rbw get NAME)`). Vault management commands like `sync`, `lock`, and `list` are untouched.
- **Won't echo a secret-shaped variable** (`secretSafety.blockSecretEnvEcho`). An `echo` or `printf` of a variable whose name looks like a secret (contains TOKEN, SECRET, PASSWORD, PASSPHRASE, API_KEY, ACCESS_KEY, PRIVATE_KEY, or CREDENTIAL), and `printenv` of such a variable, is refused. The normal way of feeding a token to a command still works, because it is an assignment and not an echo: `GH_TOKEN=$(gh auth token) git push`.

### Plan integrity (`planIntegrity`)

Protects the discipline behind our numbered plan files (the ones under `.claude/user-plans/`).

- **Won't mark a task complete without your sign-off** (`planIntegrity.requireSignoffBeforeComplete`). Flipping a task to `TASK:COMPLETE` is refused unless the session was launched with `CLAUDE_TASK_SIGNOFF=1`. That variable is your attestation, as the human, that you reviewed the work and the "present it and stop for review" step actually happened. Because it can only be set at launch, Claude cannot sign off on its own behalf. One thing to know: the sign-off is per session, not per task - once set, it green-lights every completion marked in that session.
- **Won't allow a malformed status change** (`planIntegrity.enforceStatusTransitions`). A task cannot jump straight from `TASK:PENDING` to `TASK:COMPLETE` (it has to pass through `IN_PROGRESS` first), and a completion has to record a date like `(2026-09-14)`. This enforces the shape of a status change, not whether the underlying work is truly finished - that judgment is still yours.

## Turning a rule off

Each rule above is an individually toggleable option under `programs.claude-code.hooks.<category>.<rule>` in your Home Manager configuration. To disable one rule, set it false, for example:

```nix
programs.claude-code.hooks.gitSafety.blockCommitOnMain = false;
```

To disable a whole category at once, set its master switch false (for example `programs.claude-code.hooks.gitSafety.enable = false`). After changing the config, run a `home-manager switch` to apply it.

Use a permanent toggle when a rule simply does not match how you work (a repository where committing on `main` is correct, an account that does not use the numbered-plan workflow). Use the launch-time `CLAUDE_HOOKS_BYPASS=1` when the rule is right in general but you need a one-off exception for a single session.

## A note for shared images

These guardrails ship with the Claude Code module, so any team member or downstream config that uses the module inherits them. The plan-integrity rules in particular assume our numbered-plan, sign-off workflow; a consumer who does not use that workflow will want to disable `planIntegrity` (or its sub-rules) in their own configuration, otherwise every attempt to mark a plan task complete will be blocked unless they launch with the sign-off variable set.
