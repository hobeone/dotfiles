set   all&
" reasonable defaults for indentation
set autoindent nocindent nosmartindent

set textwidth=79
set tabstop=2
set softtabstop=2
set expandtab

"ignore case in searches
set ignorecase

"       autowrite: Automatically save modifications to files
"       when you use critical (rxternal) commands.
set   autowrite
"
"       backup:  backups are for wimps  ;-)
"  set   backup
set nobackup
" write a backup file before overwriting a file
set nowb
" keep a backup after overwriting a file
set nobk
"
"       compatible:  Let Vim behave like Vi?  Hell, no!
set   nocompatible
"
"       comments default: sr:/*,mb:*,el:*/,://,b:#,:%,:XCOMM,n:>,fb:-
"set   comments=b:#,:%,fb:-,n:>,n:)

"
"       errorbells: damn this beep!  ;-)
set   noerrorbells


"       helpheight: zero disables this.
set   helpheight=0

set incsearch           " search as characters are entered"

"       hlsearch :  highlight search - show the current search pattern
"       This is a nice feature sometimes - but it sure can get in the
"       way sometimes when you edit.
set   hlsearch

"       laststatus:  show status line?  Yes, always!
"       laststatus:  Even for only one buffer.
set   laststatus=2
"
"       magic:  Use 'magic' patterns  (extended regular expressions)
"       in search patterns?  Certainly!  (I just *love* "\s\+"!)
"set   magic
"
set number " show line numbers
"
"
"       report: show a report when N lines were changed.
"               report=0 thus means "show all changes"!
set   report=0
"
"       ruler:       show cursor position?  Yep!
set   ruler

"       shiftwidth:  Number of spaces to use for each
"                    insertion of (auto)indent.
set   shiftwidth=2
"
"       shortmess:   Kind of messages to show.   Abbreviate them all!
"          New since vim-5.0v: flag 'I' to suppress "intro message".
set   shortmess=tI
"
"       showcmd:     Show current uncompleted command?  Absolutely!
set   showcmd

set cursorline          " highlight current line

set lazyredraw " redraw only when we need to.
"
"       showmatch:   Show the matching bracket for the last ')'?
set   showmatch
"
"       showmode:    Show the current mode?  YEEEEEEEEESSSSSSSSSSS!
set   showmode
"
"       startofline:  no:  do not jump to first character with page
"       commands, ie keep the cursor in the current column.
set nostartofline
"
set   splitbelow
"
"       title:
set title

"       visualbell:
set   visualbell


"set   highlight=8r,db,es,hs,mb,Mr,nu,rs,sr,tb,vr,ws


" allows files to be open in invisible buffers
set hidden

" make backspace "more powerful"
set backspace=indent,eol,start

" keep undo files in one place
set undodir=~/.vim/undodir

" get mouse working
"set mouse=a


" ----- bling/vim-airline settings -----
" Always show statusbar
set laststatus=2

" Fancy arrow symbols, requires a patched font
" To install a patched font, run over to
"     https://github.com/abertsch/Menlo-for-Powerline
" download all the .ttf files, double-click on them and click "Install"
" Finally, uncomment the next line
"let g:airline_powerline_fonts = 1

" Show PASTE if in paste mode
let g:airline_detect_paste=1

" Show airline for tabs too
let g:airline#extensions#tabline#enabled = 1


"
" ===================================================================
" AutoCommands
" ===================================================================
"
" More coding sytle colors

autocmd ColorScheme * highlight ExtraWhitespace ctermbg=red guibg=red
autocmd Syntax * syn match ExtraWhitespace /\s\+$/
autocmd BufWinEnter * match ExtraWhitespace /\s\+$/

autocmd ColorScheme * highlight Tabs ctermbg=red guibg=red
autocmd Syntax * syn match Tabs "\t"
autocmd BufWinEnter * match Tabs "\t"

" Bright red background for text matches
autocmd ColorScheme * highlight Search ctermbg=red ctermfg=white guifg=#FFFFFF guibg=#FF0000

" Override italics in gui colorschemes
autocmd ColorScheme * highlight Comment gui=NONE

" Force a black background in the colorschme
autocmd ColorScheme * highlight Normal guibg=black

" autocmd ColorScheme * highlight Cursor ctermfg=white ctermbg=black guifg=black guibg=white

"autocmd ColorScheme * highlight CursorLine cterm=NONE ctermbg=darkgrey ctermfg=white guibg=darkgrey guifg=white 

" Go wants tabs so don't highlight or expand them,
autocmd BufWinEnter *.go match Tabs "\t\+$"
autocmd BufWinLeave *.go match Tabs "\t"


call pathogen#infect()
syntax on
filetype on
filetype plugin indent on

let g:solarized_termcolors = 256
"let g:solarized_visibility = "high"
"let g:solarized_contrast = "high"


if has("gui_running")
  set guifont=terminus\ bold\ 12 linespace=0
  "set guifont=Source\ Code\ Pro\ 11 linespace=-2
  "no toolbar
  set guioptions-=T
  set bg=dark
  set antialias
  colorscheme vividchalk
else
  set t_Co=256
  set bg=dark
  colorscheme solarized
endif

set modeline modelines=3

" don't show help when F1 is pressed -- I press it too much by accident
map <F1> <ESC>
"map! <F1> <ESC>
inoremap <F1> <ESC>


augroup mkd
  autocmd BufRead *.mkd  set ai formatoptions=tcroqn2 comments=n:>
augroup END



" Reopen files at the last seen line
:au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal g'\"" | endif

" Wrapping and tabs.
autocmd BufRead *.py set tw=78 ts=2 sw=2 sta et sts=2 ai

" More syntax highlighting.
let python_highlight_all = 1

" Smart indenting
autocmd BufRead *.py set indentexpr=GetGooglePythonIndent(v:lnum)

" Auto completion via ctrl-space (instead of the nasty ctrl-x ctrl-o)
"set omnifunc=pythoncomplete#Complete
"inoremap <Nul> <C-x><C-o>

" http://code.google.com/p/google-styleguide/source/browse/trunk/google_python_style.vim

let s:maxoff = 50 " maximum number of lines to look backwards.

function GetGooglePythonIndent(lnum)

  " Indent inside parens.
  " Align with the open paren unless it is at the end of the line.
  " E.g.
  "   open_paren_not_at_EOL(100,
  "                         (200,
  "                          300),
  "                         400)
  "   open_paren_at_EOL(
  "       100, 200, 300, 400)
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

  " Delegate the rest to the original function.
  return GetPythonIndent(a:lnum)

endfunction

let pyindent_nested_paren="&sw*2"
let pyindent_open_paren="&sw*2"

set formatoptions+=ctrq

" Enable spell checking, even in program source files. Hit <F4> to highlight
" highlight spelling errors. Hit it again to turn highlighting off.
"
" And, if you cannot remember the keybindings, and/or too lazy to type
"
"     :help spell

" and read the manual, here is a brief reminder:
" ]s Next misspelled word
" [s Previous misspelled word
" z= Make suggestions for current word
" zg Add to good words list
"
if has("spell")
  setlocal spell spelllang=en_us  " American English spelling.

  " Toggle spelling with F4 key.
  map <F4> :set spell!<CR><Bar>:echo "Spell check: " . strpart("OffOn", 3 * &spell, 3)<CR>

  " z= for suggestions

  " Change the default highlighting colors and terminal attributes
  highlight SpellBad cterm=underline ctermfg=yellow ctermbg=gray

  " Limit list of suggestions to the top 10 items
  set sps=best,10

  "Turn spelling off by default for English UK.
  "Center is correctly spelled. Centre is not, and
  "shows with spell local colors. Misspelled words
  "show like soo.
  set nospell
endif

set omnifunc=syntaxcomplete#Complete
let g:UltiSnipsSnippetDirectories=["UltiSnips","vim-snippets/UltiSnips", "snippets/angular/UltiSnips", "bundle/vim-go/gosnippets/UltiSnips"]
" Needed for YCM compat
let g:UltiSnipsExpandTrigger="<c-j>"
let g:UltiSnipsJumpForwardTrigger="<c-j>"
let g:UltiSnipsJumpBackwardTrigger="<c-k>"

" ----- Raimondi/delimitMate settings -----
let delimitMate_expand_cr = 1
augroup mydelimitMate
  au!
  au FileType markdown let b:delimitMate_nesting_quotes = ["`"]
  au FileType tex let b:delimitMate_quotes = ""
  au FileType tex let b:delimitMate_matchpairs = "(:),[:],{:},`:'"
  au FileType python let b:delimitMate_nesting_quotes = ['"', "'"]
augroup END

" Force YCM to call out to the gocode omnifunc for everything.
let g:ycm_semantic_triggers = {
\  'go'  : [' '],
\ }

let g:go_fmt_command = "goimports"

" Turn on highlighting for go
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_structs = 1
let g:go_highlight_interfaces = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1

" ----- scrooloose/syntastic settings -----

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

let g:syntastic_error_symbol = '✘'
let g:syntastic_warning_symbol = "▲"
let g:syntastic_aggregate_errors = 1
let g:syntastic_go_checkers = ['go', 'gotype', 'golint', 'govet']

let g:syntastic_html_tidy_ignore_errors=[" proprietary attribute \"ng-", " proprietary attribute \"ui-"]

au Filetype go nnoremap <leader>v :sp <CR>:exe "GoDef" <CR>

nmap <F6> :TagbarToggle<CR>
let g:tagbar_type_go = {  
    \ 'ctagstype' : 'go',
    \ 'kinds'     : [
        \ 'p:package',
        \ 'i:imports:1',
        \ 'c:constants',
        \ 'v:variables',
        \ 't:types',
        \ 'n:interfaces',
        \ 'w:fields',
        \ 'e:embedded',
        \ 'm:methods',
        \ 'r:constructor',
        \ 'f:functions'
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 't' : 'ctype',
        \ 'n' : 'ntype'
    \ },
    \ 'scope2kind' : {
        \ 'ctype' : 't',
        \ 'ntype' : 'n'
    \ },
    \ 'ctagsbin'  : 'gotags',
    \ 'ctagsargs' : '-sort -silent'
\ }

" Don't wrap html
autocmd BufWinEnter *.html set textwidth=0
autocmd BufWinEnter *.html set wrapmargin=0

" Javascript
let g:used_javascript_libs = 'angular, angularui'

source ~/.vim/user.vim
