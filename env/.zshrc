# Add deno completions to search path
if [[ ":$FPATH:" != *":/home/nick/.zsh/completions:"* ]]; then export FPATH="/home/nick/.zsh/completions:$FPATH"; fi
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
	git
	zsh-autosuggestions
	history-substring-search
	fast-syntax-highlighting
	zsh-autocomplete
)
# Enable asynchronous suggestion fetching
ZSH_AUTOSUGGEST_USE_ASYNC=1

# Limit buffer size to prevent lag on large inputs or pasting
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# Disable automatic widget re-binding for better performance
ZSH_AUTOSUGGEST_MANUAL_REBIND=1Copied!

[ -f "$ZSH/oh-my-zsh.sh" ] && source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# NVM configuration removed - handled by installer
eval "$(starship init zsh)"

GPG_TTY=$(tty)
export GPG_TTY

path+=("$HOME/.local/bin")
path+=("$HOME/install/configs/private/.local/bin")
export PATH

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

#if [ "$TMUX" = "" ]; then
#	tmux new-session "bash $HOME/.local/bin/tmux_startup"
#fi

# pnpm
export PNPM_HOME="/home/nick/.local/share/pnpm"
case ":$PATH:" in
*":$PNPM_HOME:"*) ;;
*) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

_zsh_cli_fg() { fg; }
zle -N _zsh_cli_fg
bindkey '^Z' _zsh_cli_fg

# bun completions
[ -s "/home/nick/.bun/_bun" ] && source "/home/nick/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH=$PATH:/usr/local/go/bin

eval "$(zoxide init zsh)"

# Download Znap, if it's not there yet.
# [[ -r ~/Repos/znap/znap.zsh ]] ||
#     git clone --depth 1 -- \
#         https://github.com/marlonrichert/zsh-snap.git ~/Repos/znap
# source ~/Repos/znap/znap.zsh  # Start Znap

# https://github.com/sharkdp/fd
nvim_config=($(fd --max-depth 1 --glob 'nvim-*' ~/.config))
for config in $nvim_config; do
	config_name=$(basename $config)
	alias "$config_name"="NVIM_APPNAME=$config_name nvim $@"
done

alias labymod="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia labymodlauncher"
alias tmuxls="tmux-sessionizer"
alias vi="nvim"

alias nodekill="lsof -t -i:8080 | xargs -r kill"
alias waybarrestart="killall -SIGUSR2 waybar"
# alias tmux="~/.local/bin/tmux_startup"

vv() {
	# Assumes all configs exist in directories named ~/.config/nvim-*
	local config=$(fd --max-depth 1 --glob 'nvim-*' ~/.config | sed '1i ~/.config/nvim' | fzf --prompt="Neovim Configs > " --height=~50% --layout=reverse --border --exit-0)

	# If I exit fzf without selecting a config, don't open Neovim
	[[ -z $config ]] && echo "No config selected" && return

	# Open Neovim with the selected config
	if [[ $config == *"nvim-"* ]]; then
		NVIM_APPNAME=$(basename $config) nvim $@
	else
		nvim $@
	fi
}

fpath+=${ZDOTDIR:-~}/.zsh_functions

[ -f ~/.env ] && {
    set -o allexport
    source ~/.env
    set +o allexport
}
[ -f "/home/nick/.deno/env" ] && . "/home/nick/.deno/env"

autoload -Uz compinit
compinit

# Load Deno environment if it exists
[ -f "$HOME/.deno/env" ] && . "$HOME/.deno/env"

# Load Deno bash completion if it exists
[ -f "$HOME/.local/share/bash-completion/completions/deno.bash" ] && source "$HOME/.local/share/bash-completion/completions/deno.bash"

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Deno
export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
export SSH_AUTH_SOCK

if ! ssh-add -l >/dev/null 2>&1; then
  rm -f "$SSH_AUTH_SOCK"
  eval "$(ssh-agent -s -a "$SSH_AUTH_SOCK")" >/dev/null
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

