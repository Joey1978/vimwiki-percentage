" ============================================================================
" File:        vimwiki_percentage.vim
" Description: Add VimOutliner-style percentage completion to Vimwiki checkboxes
" Author:      Your Name
" License:     MIT
" ============================================================================

" Guard against multiple loads and ensure Vimwiki is available
if exists("g:loaded_vimwiki_percentage") || &cp
  finish
endif

" Don't load if Vimwiki isn't available
if !exists('g:loaded_vimwiki')
  echom "VimwikiPercentage: Vimwiki not found. Please install Vimwiki first."
  finish
endif

let g:loaded_vimwiki_percentage = 1

" Save compatible mode
let s:save_cpo = &cpo
set cpo&vim

" Configuration
if !exists('g:vimwiki_percentage_enabled')
  let g:vimwiki_percentage_enabled = 1
endif

if !exists('g:vimwiki_percentage_auto_update')
  let g:vimwiki_percentage_auto_update = 1
endif

" Checkbox states mapping (VimOutliner style)
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

" Simple checkbox pattern (compatible with both markdown and default syntax)
function! s:get_checkbox_pattern()
  return '^\s*\([*+-]\)\s\+\[\([^]]*\)\]\(.*\)$'
endfunction

" Extract percentage from end of line
function! s:extract_percentage(line)
  let match = matchlist(a:line, '\s\(\d\+\)%\s*$')
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

" Check if current line has a checkbox
function! s:is_checkbox_line()
  let line = getline('.')
  return line =~ s:get_checkbox_pattern()
endfunction

" Update checkbox percentage display
function! s:update_checkbox_percentage()
  if !s:is_checkbox_line()
    return
  endif
  
  let line = getline('.')
  let pattern = s:get_checkbox_pattern()
  let match = matchlist(line, pattern)
  
  if empty(match)
    return
  endif
  
  let bullet = match[1]
  let checkbox_state = match[2]
  let rest_of_line = match[3]
  
  " Remove existing percentage
  let rest_of_line = substitute(rest_of_line, '\s\+\d\+%\s*$', '', '')
  
  " Calculate percentage from checkbox state
  let percentage = s:state_to_percentage(checkbox_state)
  
  " Add percentage display (show for all states except empty)
  if percentage > 0
    let rest_of_line = rest_of_line . ' ' . percentage . '%'
  endif
  
  " Reconstruct line
  let indent = matchstr(line, '^\s*')
  let new_line = indent . bullet . ' [' . checkbox_state . ']' . rest_of_line
  call setline('.', new_line)
endfunction

" Calculate completion percentage from child items
function! s:calculate_child_percentage(start_line)
  let current_line = a:start_line + 1
  let current_indent = indent(a:start_line)
  let total_children = 0
  let completed_percentage = 0
  let pattern = s:get_checkbox_pattern()
  
  while current_line <= line('$')
    let line_content = getline(current_line)
    let line_indent = indent(current_line)
    
    " Stop if we've reached same or lesser indentation (non-empty line)
    if line_indent <= current_indent && line_content !~ '^\s*$'
      break
    endif
    
    " Skip empty lines
    if line_content =~ '^\s*$'
      let current_line += 1
      continue
    endif
    
    " Only process direct children (one level deeper)
    if line_indent == current_indent + (&shiftwidth > 0 ? &shiftwidth : 2)
      let match = matchlist(line_content, pattern)
      if !empty(match)
        let total_children += 1
        let state = match[2]
        
        " Check for existing percentage first
        let existing_perc = s:extract_percentage(line_content)
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
  
  return float2nr(completed_percentage * 1.0 / total_children)
endfunction

" Update parent checkboxes based on children
function! s:update_parent_percentage()
  let current_line = line('.')
  let pattern = s:get_checkbox_pattern()
  
  " Find parent checkbox
  let parent_line = current_line - 1
  let current_indent = indent(current_line)
  
  while parent_line > 0
    let parent_content = getline(parent_line)
    let parent_indent = indent(parent_line)
    
    " Found a potential parent (less indented, non-empty)
    if parent_indent < current_indent && parent_content !~ '^\s*$'
      let match = matchlist(parent_content, pattern)
      if !empty(match)
        " This is a parent checkbox
        let child_percentage = s:calculate_child_percentage(parent_line)
        
        if child_percentage >= 0
          " Update parent state and percentage
          let new_state = s:percentage_to_checkbox_state(child_percentage)
          let bullet = match[1]
          let rest_of_line = match[3]
          
          " Remove existing percentage
          let rest_of_line = substitute(rest_of_line, '\s\+\d\+%\s*$', '', '')
          
          " Add new percentage
          if child_percentage > 0
            let rest_of_line = rest_of_line . ' ' . child_percentage . '%'
          endif
          
          " Update the line
          let indent_str = matchstr(parent_content, '^\s*')
          let new_content = indent_str . bullet . ' [' . new_state . ']' . rest_of_line
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

" Main toggle function
function! VimwikiPercentageToggle()
  " Use Vimwiki's built-in toggle if available
  try
    if exists('*vimwiki#lst#toggle_list_item')
      call vimwiki#lst#toggle_list_item()
    endif
  catch
    " Fallback: simple manual toggle
    call s:simple_toggle()
  endtry
  
  if g:vimwiki_percentage_enabled
    call s:update_checkbox_percentage()
    
    if g:vimwiki_percentage_auto_update
      call s:update_parent_percentage()
    endif
  endif
endfunction

" Simple fallback toggle
function! s:simple_toggle()
  if !s:is_checkbox_line()
    return
  endif
  
  let line = getline('.')
  let pattern = s:get_checkbox_pattern()
  let match = matchlist(line, pattern)
  
  if !empty(match)
    let current_state = match[2]
    let new_state = ' '
    
    " Cycle through states
    if current_state == ' '
      let new_state = '.'
    elseif current_state == '.'
      let new_state = '-'
    elseif current_state == '-'
      let new_state = '+'
    elseif current_state == '+'
      let new_state = 'X'
    else
      let new_state = ' '
    endif
    
    " Replace checkbox state
    let new_line = substitute(line, '\[\([^]]*\)\]', '[' . new_state . ']', '')
    call setline('.', new_line)
  endif
endfunction

" Set custom percentage
function! VimwikiSetPercentage(percentage)
  if !s:is_checkbox_line()
    echo "No checkbox found on current line"
    return
  endif
  
  let percentage = max([0, min([100, a:percentage])])
  let new_state = s:percentage_to_checkbox_state(percentage)
  
  let line = getline('.')
  let pattern = s:get_checkbox_pattern()
  let match = matchlist(line, pattern)
  
  if !empty(match)
    let bullet = match[1]
    let rest_of_line = match[3]
    
    " Remove existing percentage
    let rest_of_line = substitute(rest_of_line, '\s\+\d\+%\s*$', '', '')
    
    " Add new percentage
    if percentage > 0
      let rest_of_line = rest_of_line . ' ' . percentage . '%'
    endif
    
    " Update the line
    let indent_str = matchstr(line, '^\s*')
    let new_line = indent_str . bullet . ' [' . new_state . ']' . rest_of_line
    call setline('.', new_line)
    
    if g:vimwiki_percentage_auto_update
      call s:update_parent_percentage()
    endif
  endif
endfunction

" Update all percentages
function! VimwikiUpdatePercentages()
  call s:update_checkbox_percentage()
  if g:vimwiki_percentage_auto_update
    call s:update_parent_percentage()
  endif
endfunction

" Commands
command! -nargs=1 VimwikiSetPercentage call VimwikiSetPercentage(<args>)
command! VimwikiUpdatePercentages call VimwikiUpdatePercentages()

" Setup function called after Vimwiki initialization
function! s:setup_vimwiki_percentage()
  if !exists('b:vimwiki_percentage_setup') && &filetype == 'vimwiki'
    let b:vimwiki_percentage_setup = 1
    
    " Buffer-local mappings
    nnoremap <buffer> <silent> <C-Space> :call VimwikiPercentageToggle()<CR>
    nnoremap <buffer> <leader>wp :VimwikiSetPercentage 
    nnoremap <buffer> <silent> <leader>wu :call VimwikiUpdatePercentages()<CR>
  endif
endfunction

" Autocommands - delayed setup to avoid conflicts
augroup VimwikiPercentage
  autocmd!
  " Setup after Vimwiki buffer is fully initialized
  autocmd FileType vimwiki call s:setup_vimwiki_percentage()
  " Also try on BufEnter for existing buffers
  autocmd BufEnter *.wiki call s:setup_vimwiki_percentage()
augroup END

" Restore compatible mode
let &cpo = s:save_cpo
unlet s:save_cpo