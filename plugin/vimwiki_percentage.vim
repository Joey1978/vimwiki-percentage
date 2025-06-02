" ============================================================================
" File:        vimwiki_percentage.vim
" Description: Add VimOutliner-style percentage completion to Vimwiki checkboxes
" Author:      Your Name
" License:     MIT
" ============================================================================

if exists("g:loaded_vimwiki_percentage") || &cp
  finish
endif
let g:loaded_vimwiki_percentage = 1

" Configuration
if !exists('g:vimwiki_percentage_enabled')
  let g:vimwiki_percentage_enabled = 1
endif

if !exists('g:vimwiki_percentage_auto_update')
  let g:vimwiki_percentage_auto_update = 1
endif

" Checkbox states mapping
let s:checkbox_states = {
  \ ' ': 0,
  \ '.': 25,
  \ '-': 50,
  \ '+': 75,
  \ 'X': 100,
  \ 'x': 100
  \ }

let s:percentage_to_state = {
  \ 0: ' ',
  \ 25: '.',
  \ 50: '-',
  \ 75: '+',
  \ 100: 'X'
  \ }

" Get checkbox pattern for current wiki syntax
function! s:get_checkbox_pattern()
  if exists('g:vimwiki_list') && len(g:vimwiki_list) > 0
    let syntax = vimwiki#vars#get_wikilocal('syntax')
    if syntax == 'markdown'
      return '\v^\s*[-*+]\s+\[(.)\](.*)$'
    else
      return '\v^\s*\*\s+\[(.)\](.*)$'
    endif
  endif
  return '\v^\s*[-*+]\s+\[(.)\](.*)$'
endfunction

" Extract percentage from line
function! s:extract_percentage(line)
  let match = matchlist(a:line, '\v\s+(\d+)%\s*$')
  if !empty(match)
    return str2nr(match[1])
  endif
  return -1
endfunction

" Calculate percentage from checkbox state
function! s:state_to_percentage(state)
  if has_key(s:checkbox_states, a:state)
    return s:checkbox_states[a:state]
  endif
  return 0
endfunction

" Convert percentage to checkbox state
function! s:percentage_to_checkbox_state(percentage)
  " Find closest percentage
  let closest = 0
  let min_diff = 100
  for perc in keys(s:percentage_to_state)
    let diff = abs(a:percentage - perc)
    if diff < min_diff
      let min_diff = diff
      let closest = perc
    endif
  endfor
  return s:percentage_to_state[closest]
endfunction

" Update checkbox percentage display
function! s:update_checkbox_percentage()
  let line = getline('.')
  let pattern = s:get_checkbox_pattern()
  let match = matchlist(line, pattern)
  
  if empty(match)
    return
  endif
  
  let checkbox_state = match[1]
  let rest_of_line = match[2]
  
  " Remove existing percentage
  let rest_of_line = substitute(rest_of_line, '\v\s+\d+%\s*$', '', '')
  
  " Calculate percentage from checkbox state
  let percentage = s:state_to_percentage(checkbox_state)
  
  " Add percentage if not 0% or 100%
  if percentage > 0 && percentage < 100
    let rest_of_line = rest_of_line . ' ' . percentage . '%'
  elseif percentage == 100
    let rest_of_line = rest_of_line . ' 100%'
  endif
  
  " Reconstruct line
  let indent = matchstr(line, '^\s*')
  let bullet = matchstr(line, '\v^\s*\zs[-*+]\ze\s+\[')
  if empty(bullet)
    let bullet = '*'
  endif
  
  let new_line = indent . bullet . ' [' . checkbox_state . ']' . rest_of_line
  call setline('.', new_line)
endfunction

" Calculate child completion percentage
function! s:calculate_child_percentage(start_line)
  let current_line = a:start_line + 1
  let current_indent = indent(a:start_line)
  let total_children = 0
  let completed_percentage = 0
  let pattern = s:get_checkbox_pattern()
  
  while current_line <= line('$')
    let line_indent = indent(current_line)
    
    " Stop if we've gone back to same or lesser indentation
    if line_indent <= current_indent && getline(current_line) !~ '^\s*$'
      break
    endif
    
    " Skip empty lines and deeper nested items
    if getline(current_line) =~ '^\s*$' || line_indent > current_indent + &shiftwidth
      let current_line += 1
      continue
    endif
    
    " Check if this is a direct child checkbox
    if line_indent == current_indent + &shiftwidth
      let match = matchlist(getline(current_line), pattern)
      if !empty(match)
        let total_children += 1
        let state = match[1]
        let existing_perc = s:extract_percentage(getline(current_line))
        
        if existing_perc >= 0
          let completed_percentage += existing_perc
        else
          let completed_percentage += s:state_to_percentage(state)
        endif
      endif
    endif
    
    let current_line += 1
  endwhile
  
  if total_children == 0
    return -1
  endif
  
  return float2nr(completed_percentage / total_children)
endfunction

" Update parent checkboxes with child completion
function! s:update_parent_percentage()
  let current_line = line('.')
  let pattern = s:get_checkbox_pattern()
  
  " Find parent checkbox
  let parent_line = current_line - 1
  let current_indent = indent(current_line)
  
  while parent_line > 0
    let parent_indent = indent(parent_line)
    
    if parent_indent < current_indent && getline(parent_line) !~ '^\s*$'
      let match = matchlist(getline(parent_line), pattern)
      if !empty(match)
        " Calculate percentage from children
        let child_percentage = s:calculate_child_percentage(parent_line)
        
        if child_percentage >= 0
          " Update parent checkbox state and percentage
          let new_state = s:percentage_to_checkbox_state(child_percentage)
          let line_content = getline(parent_line)
          let new_content = substitute(line_content, '\v\[(.)\]', '[' . new_state . ']', '')
          
          " Remove existing percentage
          let new_content = substitute(new_content, '\v\s+\d+%\s*$', '', '')
          
          " Add new percentage
          if child_percentage > 0 && child_percentage < 100
            let new_content = new_content . ' ' . child_percentage . '%'
          elseif child_percentage == 100
            let new_content = new_content . ' 100%'
          endif
          
          call setline(parent_line, new_content)
          
          " Recursively update grandparents
          call cursor(parent_line, 1)
          call s:update_parent_percentage()
        endif
        break
      endif
    endif
    
    let parent_line -= 1
  endwhile
  
  " Return to original position
  call cursor(current_line, 1)
endfunction

" Toggle checkbox and update percentages
function! VimwikiPercentageToggle()
  " First, do the normal vimwiki toggle
  if exists(':VimwikiToggleListItem')
    execute 'VimwikiToggleListItem'
  endif
  
  if g:vimwiki_percentage_enabled
    call s:update_checkbox_percentage()
    
    if g:vimwiki_percentage_auto_update
      call s:update_parent_percentage()
    endif
  endif
endfunction

" Set custom percentage
function! VimwikiSetPercentage(percentage)
  let line = getline('.')
  let pattern = s:get_checkbox_pattern()
  let match = matchlist(line, pattern)
  
  if empty(match)
    echo "No checkbox found on current line"
    return
  endif
  
  let percentage = max([0, min([100, a:percentage])])
  let new_state = s:percentage_to_checkbox_state(percentage)
  
  " Update checkbox state
  let new_line = substitute(line, '\v\[(.)\]', '[' . new_state . ']', '')
  
  " Remove existing percentage
  let new_line = substitute(new_line, '\v\s+\d+%\s*$', '', '')
  
  " Add new percentage
  if percentage > 0 && percentage < 100
    let new_line = new_line . ' ' . percentage . '%'
  elseif percentage == 100
    let new_line = new_line . ' 100%'
  endif
  
  call setline('.', new_line)
  
  if g:vimwiki_percentage_auto_update
    call s:update_parent_percentage()
  endif
endfunction

" Commands
command! -nargs=1 VimwikiSetPercentage call VimwikiSetPercentage(<args>)
command! VimwikiUpdatePercentages call s:update_checkbox_percentage() | call s:update_parent_percentage()

" Mappings (only in vimwiki files)
augroup VimwikiPercentage
  autocmd!
  autocmd FileType vimwiki nnoremap <buffer> <C-Space> :call VimwikiPercentageToggle()<CR>
  autocmd FileType vimwiki nnoremap <buffer> <leader>wp :call VimwikiSetPercentage(
  autocmd FileType vimwiki nnoremap <buffer> <leader>wu :call s:update_checkbox_percentage()<CR>:call s:update_parent_percentage()<CR>
augroup END

" Syntax highlighting for percentages
augroup VimwikiPercentageSyntax
  autocmd!
  autocmd FileType vimwiki syntax match VimwikiPercentage '\v\d+%' contained
  autocmd FileType vimwiki highlight link VimwikiPercentage Number
augroup END