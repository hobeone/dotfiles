" =============================================================================
" VIM CONFIGURATION
" =============================================================================

" -----------------------------------------------------------------------------
" 1. System & Initialization
" -----------------------------------------------------------------------------
set nocompatible              " Use Vim defaults instead of Vi
set encoding=utf-8            " Standard encoding
set hidden                    " Allow files to be open in invisible buffers
set backspace=indent,eol,start " Make backspace behave more intuitively
set modeline                  " Support modelines
set modelines=3               " Search first/last 3 lines for modelines
set lazyredraw                " Only redraw when necessary
set autowrite                 " Save modified files on external commands

" vim-plug bootstrap: Automatically download vim-plug if missing
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source ~/.vimrc
endif

let g:ale_completion_enabled = 1

" -----------------------------------------------------------------------------
" 2. Plugin Management (vim-plug)
" -----------------------------------------------------------------------------
call plug#begin('~/.vim/plugged')

" UI & Aesthetics
Plug 'ghifarit53/tokyonight-vim'
Plug 'itchyny/lightline.vim'

" Navigation & File Management
Plug 'scrooloose/nerdtree'
Plug 'majutsushi/tagbar'
Plug 'christoomey/vim-tmux-navigator'

" Editing Support
Plug 'raimondi/delimitmate'
Plug 'alpaca-tc/vim-endwise'
Plug 'godlygeek/tabular'
Plug 'sirver/ultisnips'
Plug 'honza/vim-snippets'
Plug 'dense-analysis/ale'

" Language Support
Plug 'fatih/vim-go', { 'for': 'go' }
Plug 'rust-lang/rust.vim'
Plug 'vim-ruby/vim-ruby'
Plug 'tpope/vim-rails'
Plug 'pangloss/vim-javascript'
Plug 'chr4/nginx.vim'
Plug 'hashivim/vim-terraform'
" Additional plugins found in filesystem
Plug 'tpope/vim-sensible'
"Plug 'ycm-core/YouCompleteMe'

call plug#end()
filetype plugin indent on    " Required: Enable filetype detection, plugins, and indent


let g:ale_linters = {
\   'go': ['gopls', 'golangci-lint'],
\}
let g:ale_fixers = {
\   '*': ['remove_trailing_lines', 'trim_whitespace'],
\   'go': ['goimports'],
\}
let g:ale_go_golangci_lint_package = 1
let g:ale_fix_on_save = 1

" -----------------------------------------------------------------------------
" 3. Interface & Appearance
" -----------------------------------------------------------------------------
syntax on                     " Enable syntax highlighting
set termguicolors             " Enable 24-bit RGB colors
set background=dark           " Use dark background

" --- Custom Highlight Groups ---
" We define these early and add an autocmd to re-apply them on colorscheme change.
function! s:SetupCustomHighlights()
  highlight ExtraWhitespace ctermbg=red guibg=red
  highlight Tabs ctermbg=red guibg=red
  "highlight Search ctermbg=red ctermfg=white guifg=#FFFFFF guibg=#FF0000
  "highlight Comment gui=NONE
  "highlight Normal guibg=black
endfunction

augroup CustomHighlights
  autocmd!
  autocmd ColorScheme * call s:SetupCustomHighlights()
augroup END

" Initial definition
call s:SetupCustomHighlights()

" Colorscheme Configuration
let g:tokyonight_style = 'night'
let g:tokyonight_enable_italic = 1
colorscheme tokyonight

" UI Toggles & Indicators
set number                    " Show line numbers
set ruler                     " Show cursor position
set cursorline                " Highlight the current line
set showcmd                   " Show current uncompleted command
set showmode                  " Always show the current mode
set showmatch                 " Show matching brackets
set title                     " Set window title to filename
set laststatus=2              " Always show status bar
set helpheight=0              " Disable minimum help window height

" Messages & Bells
set shortmess=tI              " Abbreviate messages; suppress intro
set report=0                  " Show all changes
set noerrorbells              " Disable beeps
set visualbell                " Use visual flash instead of beep

" -----------------------------------------------------------------------------
" 4. Indentation & Formatting
" -----------------------------------------------------------------------------
set autoindent                " Copy indent from current line
set nocindent nosmartindent   " Disable C-style/smart indenting by default
set expandtab                 " Use spaces instead of tabs
set tabstop=2                 " Number of visual spaces per TAB
set softtabstop=2             " Number of spaces in tab when editing
set shiftwidth=2              " Number of spaces to use for autoindent
set textwidth=79              " Standard line width
set formatoptions+=ctrq        " Control formatting behavior

" -----------------------------------------------------------------------------
" 5. Search & Completion
" -----------------------------------------------------------------------------
set ignorecase                " Ignore case in search patterns
set incsearch                 " Show search results as you type
set hlsearch                  " Highlight all search matches


" -----------------------------------------------------------------------------
" 6. Backups, Undo, & Sessions
" -----------------------------------------------------------------------------
set nobackup                  " Don't keep backup files
set nowritebackup             " Don't write backup before overwriting
set undodir=~/.vim/undodir     " Centralize undo files
set undofile                   " Enable persistent undo
set sessionoptions-=options   " Don't save runtimepath in sessions

" -----------------------------------------------------------------------------
" 7. Key Mappings
" -----------------------------------------------------------------------------
" Navigation
nmap <C-n> :bnext<CR>         " Next buffer
nmap <C-p> :bprev<CR>         " Previous buffer
nnoremap <C-g> :NERDTreeToggle<CR> " Toggle NERDTree
nmap <F6> :TagbarToggle<CR>    " Toggle Tagbar

" Misc Shortcuts
map <F1> <ESC>                " Disable F1 help (I press it by accident)
inoremap <F1> <ESC>

" Spell Checking
if has("spell")
  set spelllang=en_us
  set nospell                 " Off by default
  set sps=best,10             " Max 10 suggestions
  " Toggle spelling with F4
  map <F4> :set spell!<CR><Bar>:echo "Spell check: " . strpart("OffOn", 3 * &spell, 3)<CR>
  highlight SpellBad cterm=underline ctermfg=yellow ctermbg=gray
endif

" -----------------------------------------------------------------------------
" 8. Plugin Configurations
" -----------------------------------------------------------------------------
" ALE (Asynchronous Lint Engine)
let g:ale_sign_warning = '▲'
let g:ale_sign_error = '✗'
highlight link ALEWarningSign String
highlight link ALEErrorSign Title

" Lightline
let g:lightline = {
\ 'colorscheme': 'tokyonight',
\ 'active': {
\   'left': [['mode', 'paste'], ['filename', 'modified']],
\   'right': [['lineinfo'], ['percent'], ['readonly', 'linter_warnings', 'linter_errors', 'linter_ok']]
\ },
\ 'component_expand': {
\   'linter_warnings': 'LightlineLinterWarnings',
\   'linter_errors': 'LightlineLinterErrors',
\   'linter_ok': 'LightlineLinterOK'
\ },
\ 'component_type': {
\   'readonly': 'error',
\   'linter_warnings': 'warning',
\   'linter_errors': 'error'
\ },
\ }


" UltiSnips & Snippets
let g:UltiSnipsSnippetDirectories=["UltiSnips", "vim-snippets/UltiSnips", "plugged/vim-go/gosnippets/UltiSnips"]
let g:UltiSnipsExpandTrigger="<c-j>"
let g:UltiSnipsJumpForwardTrigger="<c-j>"
let g:UltiSnipsJumpBackwardTrigger="<c-k>"

" delimitMate
let delimitMate_expand_cr = 1

" Go Support
" ALE owns gopls (completion, diagnostics, formatting) — vim-go handles tooling commands
let g:go_def_mode = 'gopls'
let g:go_info_mode = 'gopls'
let g:go_referrers_mode = 'gopls'
let g:go_rename_command = 'gopls'
let g:go_fmt_autosave = 0           " ALE handles goimports on save
let g:go_imports_autosave = 0
let g:go_diagnostics_enabled = 0    " ALE shows diagnostics
let g:go_metalinter_autosave = 0    " ALE handles golangci-lint

let g:go_highlight_functions = 1

let g:go_highlight_structs = 1
let g:go_highlight_interfaces = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_function_calls = 1
let g:go_highlight_extra_types = 1


" -----------------------------------------------------------------------------
" 9. AutoCommands & Custom Logic
" -----------------------------------------------------------------------------
augroup GeneralAutoCmds
  autocmd!
  " Reopen files at the last seen line
  autocmd BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal g'\"" | endif

  " Aesthetics: Highlight extra whitespace and tabs
  autocmd Syntax,BufWinEnter * match ExtraWhitespace /\s\+$/
  autocmd Syntax,BufWinEnter * 2match Tabs "\t"
augroup END

augroup FileTypeLogic
  autocmd!
  " Markdown
  autocmd BufRead *.mkd set ai formatoptions=tcroqn2 comments=n:>
  autocmd FileType markdown let b:delimitMate_nesting_quotes = ["`"]

  " Python
  autocmd BufRead *.py set tw=78 ts=2 sw=2 sta et sts=2 ai
  autocmd BufRead *.py let python_highlight_all = 1
  autocmd BufRead *.py set indentexpr=GetGooglePythonIndent(v:lnum)
  autocmd FileType python let b:delimitMate_nesting_quotes = ['"', "'"]

  " Go — use real tabs (goimports expects them); don't highlight them
  autocmd FileType go setlocal noexpandtab tabstop=2 shiftwidth=2
  autocmd BufWinEnter *.go match none
  autocmd FileType go nnoremap <buffer> <leader>v :sp<CR>:GoDef<CR>
  autocmd FileType go nnoremap <buffer> <leader>t :GoTest<CR>
  autocmd FileType go nnoremap <buffer> <leader>b :GoBuild<CR>
  autocmd FileType go nnoremap <buffer> <leader>c :GoCoverage<CR>
  autocmd FileType go nnoremap <buffer> <leader>i :GoInfo<CR>

  " HTML
  autocmd BufWinEnter *.html set textwidth=0 wrapmargin=0

  " YAML
  autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab

  " LaTeX
  autocmd FileType tex let b:delimitMate_quotes = ""
  autocmd FileType tex let b:delimitMate_matchpairs = "(:),[:],{:},`:'"
augroup END

" Update Lightline on ALE events
augroup ALELintUpdate
  autocmd!
  autocmd User ALELint call s:MaybeUpdateLightline()
augroup END

" -----------------------------------------------------------------------------
" 10. Helper Functions
" -----------------------------------------------------------------------------
" Lightline Linter Helpers
function! LightlineLinterWarnings() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  let l:all_errors = l:counts.error + l:counts.style_error
  let l:all_non_errors = l:counts.total - l:all_errors
  return l:counts.total == 0 ? '' : printf('%d ◆', l:all_non_errors)
endfunction

function! LightlineLinterErrors() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  let l:all_errors = l:counts.error + l:counts.style_error
  return l:counts.total == 0 ? '' : printf('%d ✗', l:all_errors)
endfunction

function! LightlineLinterOK() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  return l:counts.total == 0 ? '✓ ' : ''
endfunction

function! s:MaybeUpdateLightline()
  if exists('#lightline')
    call lightline#update()
  end
endfunction

" Python Indentation Function
let s:maxoff = 50
function! GetGooglePythonIndent(lnum)
  call cursor(a:lnum, 1)
  let [par_line, par_col] = searchpairpos('(\|{\|\[', '', ')\|}\|\]', 'bW',
        \ "line('.') < " . (a:lnum - s:maxoff) . " ? dummy :"
        \ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
        \ . " =~ '\\(Comment\\|String\\)$'")
  if par_line > 0
    call cursor(par_line, 1)
    if par_col != col("$") - 1
      return par_col
    endif
  endif
  return GetPythonIndent(a:lnum)
endfunction

" -----------------------------------------------------------------------------
" 11. Custom Source
" -----------------------------------------------------------------------------
if filereadable(expand("~/.vim/user.vim"))
  source ~/.vim/user.vim
endif
