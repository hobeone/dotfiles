# ==============================================================================
# .bashrc - Portable Bash Configuration File
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Shell Options & Behavior
# ------------------------------------------------------------------------------
# Prevent less from wrapping spaces in single quotes
export QUOTING_STYLE=literal

# Check window size after each command and update LINES and COLUMNS if necessary
shopt -s checkwinsize

# Correct minor spelling errors in cd commands
shopt -s cdspell 2>/dev/null

# Append to history file instead of overwriting it
shopt -s histappend

# Erase duplicates and ignore spaces in bash history
export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=50000
export HISTFILESIZE=100000

# Allow comments in interactive shell
shopt -s interactive_comments

# ------------------------------------------------------------------------------
# 2. Environment Variables
# ------------------------------------------------------------------------------
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export PAGER="less -r"
export EDITOR="vim"
export COLORTERM='truecolor' # Enable 24-bit color support
export LESS='-R'

# ------------------------------------------------------------------------------
# 3. Path Configuration
# ------------------------------------------------------------------------------
# Construct path dynamically based on directory existence
for dir in "$HOME/bin" "/usr/local/bin" "/usr/local/sbin" "/usr/bin" "/usr/sbin" "/bin" "/sbin" "$HOME/.local/bin" "$HOME/go/bin"; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done
export PATH

# ------------------------------------------------------------------------------
# 4. Colorized Prompt (Red for Root, Green for Users)
# ------------------------------------------------------------------------------
if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support
    COLOR_RESET="\[$(tput sgr0)\]"
    COLOR_USER="\[$(tput setaf 2)\]" # Green
    COLOR_ROOT="\[$(tput setaf 1)\]" # Red
    COLOR_DIR="\[$(tput setaf 4)\]"  # Blue
    COLOR_HOST="\[$(tput setaf 6)\]" # Cyan
else
    COLOR_RESET=""
    COLOR_USER=""
    COLOR_ROOT=""
    COLOR_DIR=""
    COLOR_HOST=""
fi

# Set the prompt based on user privilege level (root vs normal)
if [ "$EUID" -eq 0 ]; then
    PS1="${COLOR_ROOT}\u${COLOR_RESET}@${COLOR_HOST}\h${COLOR_RESET}:${COLOR_DIR}\w${COLOR_RESET}# "
else
    PS1="${COLOR_USER}\u${COLOR_RESET}@${COLOR_HOST}\h${COLOR_RESET}:${COLOR_DIR}\w${COLOR_RESET}\$ "
fi
export PS1

# ------------------------------------------------------------------------------
# 5. Aliases & Command Wrappers
# ------------------------------------------------------------------------------
# Basic aliases
alias tmux='tmux -2'
alias pgrep="pgrep -l -a"

# Safe vim alias (applies custom vimrc if it exists)
if [ -f "$HOME/.vimrc" ]; then
    alias vim='vim -X -o -u $HOME/.vimrc'
else
    alias vim='vim'
fi

# bat (cat replacement; Debian installs as batcat)
if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    alias bat='batcat'
fi
if command -v bat &>/dev/null; then
    alias cat="bat"
fi

# Modern listing tools (eza vs standard ls color support)
if command -v eza &>/dev/null; then
    alias ls="eza --no-quotes"
    alias l="eza -l --icons --no-quotes"
    alias la="eza -la --icons --no-quotes"
    alias lt="eza -T --icons --no-quotes"
    alias lan="eza -la -snew --icons --no-quotes"
else
    # Detect if OS supports colorized output on standard ls
    if ls --color=auto >/dev/null 2>&1; then
        alias ls="ls --color=auto"
    else
        alias ls="ls -G"
    fi
    alias l="ls -lhF"
    alias la="ls -lAhF"
fi

# Setup dircolors if they exist
if [ -r "$HOME/.dircolors" ]; then
    eval "$(dircolors -b "$HOME/.dircolors")"
else
    eval "$(dircolors -b)"
fi

# ------------------------------------------------------------------------------
# 6. Interactive Completions
# ------------------------------------------------------------------------------
# Load system bash completion if available
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# ------------------------------------------------------------------------------
# 7. Local Overrides
# ------------------------------------------------------------------------------
# Load ~/.bashrc.local for local overrides if it exists
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
