if exists("b:current_syntax")
  finish
endif

syn case match

syn keyword q2promenuTodo contained TODO FIXME XXX NOTE

syn match q2promenuComment "//.*$" contains=q2promenuTodo

syn region q2promenuString start=+"+ skip=+\\\\\|\\"+ end=+"+ oneline

syn match q2promenuBlockBegin "^begin\s\+\S.*$" contains=q2promenuBlockName
syn match q2promenuBlockName "[^ \t\\].*" contained containedin=q2promenuBlockBegin
syn match q2promenuBlockEnd "^end\s*$"

syn keyword q2promenuInclude      include
syn keyword q2promenuBackground   background
syn keyword q2promenuFont         font
syn keyword q2promenuCursor       cursor
syn keyword q2promenuWeapon       weapon
syn keyword q2promenuStyle        style
syn keyword q2promenuBlank        blank
syn keyword q2promenuTitle        title
syn keyword q2promenuBanner       banner

syn keyword q2promenuColor        color
syn match q2promenuColorValue "\%(normal\|active\|selection\|disabled\)" contained
syn match q2promenuHexColor "#[0-9a-fA-F]\{6\}\%([0-9a-fA-F]\{2\}\)\?" contained

syn keyword q2promenuPairsKeyword  pairs
syn keyword q2promenuValuesKeyword values
syn keyword q2promenuRangeKeyword  range
syn keyword q2promenuToggle        toggle
syn keyword q2promenuField         field
syn keyword q2promenuAction        action
syn keyword q2promenuBind          bind
syn keyword q2promenuExec          exec

syn match q2promenuFieldOpt "\-\-\%(numeric\|integer\|width\|center\|status\)"

syn match q2promenuNumber "\<\d\+\(\.\d\+\)\?\>"
syn match q2promenuFlag "\~-\=\d\+"

syn match q2promenuContinuation "\\$"

syn region q2promenuFold start="^begin\s" end="^end\s*$" transparent fold keepend

hi def link q2promenuComment      Comment
hi def link q2promenuTodo         Todo
hi def link q2promenuString       String
hi def link q2promenuBlockBegin   Structure
hi def link q2promenuBlockName    Identifier
hi def link q2promenuBlockEnd     Structure
hi def link q2promenuInclude      PreProc
hi def link q2promenuBackground   Keyword
hi def link q2promenuFont         Keyword
hi def link q2promenuCursor       Keyword
hi def link q2promenuWeapon       Keyword
hi def link q2promenuStyle        Keyword
hi def link q2promenuBlank        Keyword
hi def link q2promenuTitle        Keyword
hi def link q2promenuBanner       Keyword
hi def link q2promenuColor        Keyword
hi def link q2promenuColorValue   Special
hi def link q2promenuHexColor     Number
hi def link q2promenuPairsKeyword Keyword
hi def link q2promenuValuesKeyword Keyword
hi def link q2promenuRangeKeyword Keyword
hi def link q2promenuToggle       Keyword
hi def link q2promenuField        Keyword
hi def link q2promenuFieldOpt     Special
hi def link q2promenuAction       Keyword
hi def link q2promenuBind         Keyword
hi def link q2promenuExec         Keyword
hi def link q2promenuNumber       Number
hi def link q2promenuFlag         Number
hi def link q2promenuContinuation Special

let b:current_syntax = "q2promenu"
