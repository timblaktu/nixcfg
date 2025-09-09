# Custom aliases and functions (merged from existing ~/.profile)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in {
  config = {
    # Enhanced shell aliases from existing ~/.profile
    programs.bash.shellAliases = lib.mkAfter {
      # Enhanced ls alias from ~/.profile  
      lsblk = "lsblk -po name,vendor,model,label,size,type,fstype,mountpoints";
      
      # Navigation shortcuts from ~/.profile
      lh = "ls -lath | head";
      cds = "cd ~/src; lh";
      cdtr = "cd ~/src/tr; lh"; 
      cdmx = "cd ~/src/mxts; lh";
      cdddd = "cd ~/tr-dep-diagnostics; lh";
      
      # Git workflow shortcuts from ~/.profile
      gitit = "git commit -av && git push";
      nvtr = "(cdtr && nvim -S && gitit)";
      nvmx = "(cdmx && nvim -S && gitit)";
      nvt = "nvim ~/bin/tellclaude && tellclaude";
      
      # Debug git alias from ~/.profile
      dgit = "GIT_TRACE=true GIT_CURL_VERBOSE=true GIT_SSH_COMMAND=\"ssh -vvv\" GIT_TRACE_PACK_ACCESS=true GIT_TRACE_PACKET=true GIT_TRACE_PACKFILE=true GIT_TRACE_PERFORMANCE=true GIT_TRACE_SETUP=true GIT_TRACE_SHALLOW=true git";
      
      # Drive navigation shortcuts from ~/.profile
      cdint = "verbosecd /mnt/internal-4tb-nvme";
      cdext1 = "verbosecd /mnt/ext-tb4-4tb-nvme-1";
      cdext2 = "verbosecd /mnt/ext-tb4-4tb-nvme-2";
      cdc = "verbosecd /mnt/g";
      cdg = "verbosecd /mnt/g";
      cdx = "verbosecd /mnt/x";
      cdy = "verbosecd /mnt/y";
      cdz = "verbosecd /mnt/z";
      
      # Poetry shortcut from ~/.profile
      poetryshell = "eval $(poetry env activate)";
    };
    
    programs.zsh.shellAliases = lib.mkAfter {
      # Same aliases for zsh
      lsblk = "lsblk -po name,vendor,model,label,size,type,fstype,mountpoints";
      
      # Navigation shortcuts
      lh = "ls -lath | head";
      cds = "cd ~/src; lh";
      cdtr = "cd ~/src/tr; lh";
      cdmx = "cd ~/src/mxts; lh";
      cdddd = "cd ~/tr-dep-diagnostics; lh";
      
      # Git workflow shortcuts
      gitit = "git commit -av && git push";
      nvtr = "(cdtr && nvim -S && gitit)";
      nvmx = "(cdmx && nvim -S && gitit)";
      nvt = "nvim ~/bin/tellclaude && tellclaude";
      
      # Debug git alias
      dgit = "GIT_TRACE=true GIT_CURL_VERBOSE=true GIT_SSH_COMMAND=\"ssh -vvv\" GIT_TRACE_PACK_ACCESS=true GIT_TRACE_PACKET=true GIT_TRACE_PACKFILE=true GIT_TRACE_PERFORMANCE=true GIT_TRACE_SETUP=true GIT_TRACE_SHALLOW=true git";
      
      # Drive navigation shortcuts
      cdint = "verbosecd /mnt/internal-4tb-nvme";
      cdext1 = "verbosecd /mnt/ext-tb4-4tb-nvme-1";
      cdext2 = "verbosecd /mnt/ext-tb4-4tb-nvme-2";
      cdc = "verbosecd /mnt/g";
      
      # Poetry shortcut
      poetryshell = "eval $(poetry env activate)";
    };
    
    # Custom shell functions from existing ~/.profile
    programs.bash.initExtra = lib.mkAfter ''
      # Custom functions from existing ~/.profile
      better_less() {
        # for viewing single files, pipe it through cat first, which renders
        # ANSI colors and other special characters better than less even with -R
        if [ -f "$1" ] && [ $# -eq 1 ]; then
          cat "$1" | less -r
        else
          command less "$@"
        fi
      }
      
      verbosecd() {
        cd "$1"; ls -lath | head
      }
      
      # SSH options setup from ~/.profile
      SSHOPTS_LENIENT=( -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )
    '';
    
    programs.zsh.initContent = lib.mkAfter ''
      # Custom functions from existing ~/.profile  
      better_less() {
        if [ -f "$1" ] && [ $# -eq 1 ]; then
          cat "$1" | less -r
        else
          command less "$@"
        fi
      }
      
      verbosecd() {
        cd "$1"; ls -lath | head
      }
      
      # SSH options setup from ~/.profile
      SSHOPTS_LENIENT=( -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )
    '';
  };
}
