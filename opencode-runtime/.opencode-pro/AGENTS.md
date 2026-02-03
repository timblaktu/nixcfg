# OpenCode Configuration for User

## ESSENTIAL RULES

- ALWAYS Do what has been asked; nothing more, nothing less
- NEVER create files unless necessary to do what was asked of you
- ALWAYS prefer editing existing files to creating new ones
- ALWAYS add documentation to existing markdown files instead of creating new files
- ALWAYS think deeply about WHERE to write content when performing documentation tasks
- ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
- ALWAYS use fd to find files and ripgrep (rg) to search files
- ALWAYS ensure shell commands generated support both bash and zsh syntax
- ALWAYS ensure shell commands are concise, use minimal comments and empty lines
- Before finishing, verify your solution addresses all requirements
- After receiving tool results, carefully reflect on their quality and determine optimal next steps
- ALWAYS invoke multiple independent tools simultaneously rather than sequentially


## Git Commit Rules

- NEVER include AI identity in commit messages
- Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" footers
- Do NOT add "Generated with OpenCode" or similar AI attribution
- Write commit messages as if authored by the human user
- Keep commit messages concise and focused on the technical changes


## WSL Environment

- ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if running in WSL
- If running in WSL, access other instances' rootfs at `/mnt/wsl/$WSL_DISTRO_NAME/`


## Screenshots (WSL Dynamic Detection)

When asked to view, read, or refer to screenshots, find the most recent one(s) dynamically:

```bash
# Find most recent screenshot (~0.2s) - works across Windows usernames and OneDrive variants
fd -t f -e png -e jpg -e jpeg . '/mnt/c/Users/'*/OneDrive*/Pictures/Screenshots* -d 1 --exec stat --printf='%Y %n\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
```

- Adjust `head -1` to `head -N` for multiple screenshots
- Then use the Read tool on the returned file path(s)


## Nix Flake Projects

- ALWAYS stage relevant changed files (`git add --update` + `git add <relevant-untracked-files>`)


### MCP Servers (Current Status)

- **brave-search**: + 
- **context7**: + 
- **filesystem**: + 
- **github**: + 
- **gitlab**: + 
- **mcp-nixos**: + 
- **puppeteer**: + 
- **sequential-thinking**: + 
- **serena**: + 



