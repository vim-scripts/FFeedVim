" ==============================================================
" FFeedVim - Post to Friendfeed from Vim
"
" Version: 0.1.0
" License: Vim license. See :help license
" Language: Vim script
" Maintainer: Po Shan Cheah <morton@mortonfox.com>
" Created: May 20, 2008
" Last updated: May 23, 2008
"
" GetLatestVimScripts: 2247 1 ffeedvim.vim
" ==============================================================

" Load this module only once.
if exists('loaded_ffeedvim')
    finish
endif
let loaded_ffeedvim = 1

" Avoid side-effects from cpoptions setting.
let s:save_cpo = &cpo
set cpo&vim

let s:proxy = ""
let s:login = ""

let s:ffupdate = '-F "via=ffeedvim" http://friendfeed.com/api/share'

function! s:get_config_proxy()
    " Get proxy setting from ffeed_proxy in .vimrc or _vimrc.
    " Format is proxysite:proxyport
    let s:proxy = exists('g:ffeed_proxy') ? '-x "'.g:ffeed_proxy.'"': ""
    " If ffeed_proxy_login exists, use that as the proxy login.
    " Format is proxyuser:proxypassword
    "
    " If ffeed_proxy_login_b64 exists, use that instead. This is the proxy
    " user:password in base64 encoding.
    if exists('g:ffeed_proxy_login_b64')
	let s:proxy .= ' -H "Proxy-Authorization: Basic '.g:ffeed_proxy_login_b64.'"'
    else
	let s:proxy .= exists('g:ffeed_proxy_login') ? ' -U "'.g:ffeed_proxy_login.'"' : ''
    endif
endfunction

" Get user-config variables ffeed_proxy and ffeed_login.
function! s:get_config()
    call s:get_config_proxy()

    " Get Friendfeed login info from ffeed_login in .vimrc or _vimrc.
    " Format is username:remotekey
    "
    " Note: Get remotekey from http://friendfeed.com/remotekey
    " It is not the same as your Friendfeed login password.
    "
    " If ffeed_login_b64 exists, use that instead. This is the user:remotekey
    " in base64 encoding.
    if exists('g:ffeed_login_b64')
	let s:login = '-H "Authorization: Basic '.g:ffeed_login_b64.'"'	
    elseif exists('g:ffeed_login') && g:ffeed_login != ''
	let s:login = '-u "'.g:ffeed_login.'"'
    else
	" Beep and error-highlight 
	execute "normal \<Esc>"
	redraw
	echohl ErrorMsg
	echomsg 'Friendfeed login not set.'
	    \ 'Please add to .vimrc: let ffeed_login="USER:PASS"'
	echohl None
	return -1
    endif
    return 0
endfunction

" URL-encode a string.
function! s:url_encode(str)
    return substitute(a:str, '[^a-zA-Z_-]', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')
endfunction

" Parse link and message from a user-supplied string.
" Returns a list with the message in the first element and the link in the
" second.
function! s:parse_link(mesg)
    let linkre = '\%(http\|https\|ftp\)://\S\+'
    let mesg = a:mesg

    " Try matching with link at the start of the string.
    let matchres = matchlist(mesg, '^\('.linkre.'\)\s\+\(.*\)$')
    if matchres != []
	return [ matchres[2], matchres[1] ]
    endif
    
    " Try matching with link at the end of the string.
    let matchres = matchlist(mesg, '^\(.*\)\s\+\('.linkre.'\)$')
    if matchres != []
	return [ matchres[1], matchres[2] ]
    endif

    return [ mesg, '' ]
endfunction

" Parse comment from a message.
function! s:parse_comment(mesg)
    let matchres = matchlist(a:mesg, '^\(.*\)//\(.*\)$')
    return matchres == [] ? [ a:mesg, '' ] : [ matchres[1], matchres[2] ]
endfunction

" Parse room ID from a message.
function! s:parse_room(mesg)
    let matchres = matchlist(a:mesg, '\c^room=\(\S\+\)\s\+\(.*\)$')
    return matchres == [] ? [ a:mesg, '' ] : [ matchres[2], matchres[1] ]
endfunction

" Remove leading and trailing whitespace.
function! s:chomp(s)
    let s = substitute(a:s, '\s\+$', '', '')
    return substitute(s, '^\s\+', '', '')
endfunction

" Escape double quotes.
function! s:escape(s)
    return substitute(a:s, '"', '\\&', 'g')
endfunction

" Post a message to Friendfeed.
function! s:post_ffeed(mesg, imgfile)
    " Get user-config variables ffeed_proxy and ffeed_login.
    " We get these variables every time before posting to Friendfeed so
    " that the user can change them on the fly.
    let rc = s:get_config()
    if rc < 0
	return -1
    endif

    " Convert internal newlines to spaces.
    " Remove leading and trailing whitespace.
    let mesg = s:chomp(substitute(a:mesg, '\n', ' ', 'g'))

    " Parse out the link if user supplied one.
    let [ mesg, link ] = s:parse_link(mesg)

    let link = s:escape(link)
    let linkparm = link == '' ? '' : '-F "link='.link.'"'

    " Parse out the comment if user supplied one.
    let [ mesg, comment ] = s:parse_comment(mesg)

    let comment = s:escape(s:chomp(comment))
    let commentparm = comment == '' ? '' : '-F "comment='.comment.'"'

    " Parse out the room name if user supplied one.
    let [ mesg, room ] = s:parse_room(mesg)

    let mesg = s:escape(s:chomp(mesg))
    let mesgparm = '-F "title='.mesg.'"'

    let roomparm = room == '' ? '' : '-F "room='.room.'"'

    " Upload an image file if user supplied one.
    let imgfile = s:escape(a:imgfile)
    let imgparm = imgfile == '' ? '' : '-F "img=@'.imgfile.'"'

    if strlen(mesg) < 1
	redraw
	echohl WarningMsg
	echo "Your message was empty. It was not sent."
	echohl None
    else
	redraw
	echo "Sending update to Friendfeed..."
	let output = system('curl -s '.s:proxy.' '.s:login.' '.mesgparm.' '.imgparm.' '.linkparm.' '.commentparm.' '.roomparm.' '.s:ffupdate)
	if v:shell_error != 0
	    redraw
	    echohl ErrorMsg
	    echomsg "Error posting your Friendfeed message. Result code: ".v:shell_error
	    echomsg "Output:"
	    echomsg output
	    echohl None
	else
	    " Check for errors from Friendfeed.
	    " On errors, Friendfeed simply returns a web page with the error
	    " title in a h1 tags.
	    let matchres = matchlist(output, '<h1>\(.*\)</h1>')
	    if matchres == []
		redraw
		echo "Your Friendfeed message was sent."
	    else
		redraw
		echohl ErrorMsg
		echomsg "Friendfeed Error: ".matchres[1]
		echohl None
	    endif
	endif
    endif
endfunction

" Prompt user for Friendfeed message if not supplied and then post it.
function! s:prompt_ffeed(mesg, imgfile)
    " Do this here too to check for ffeed_login. This is to avoid having the
    " user type in the message only to be told that his configuration is
    " incomplete.
    let rc = s:get_config()
    if rc < 0
	return -1
    endif

    let mesg = a:mesg

    if mesg == ""
	call inputsave()
	let mesg = input("Message: ")
	call inputrestore()
    endif

    if mesg == ""
	redraw
	echohl WarningMsg
	echo "No message provided. Not posted to Friendfeed."
	echohl None
	return
    endif

    call s:post_ffeed(mesg, a:imgfile)
endfunction

" Prompt user for image file if not supplied and then post to Friendfeed.
function! s:prompt_image_ffeed(mesg, imgfile)
    " Do this here too to check for ffeed_login. This is to avoid having the
    " user type in the message only to be told that his configuration is
    " incomplete.
    let rc = s:get_config()
    if rc < 0
	return -1
    endif

    let imgfile = a:imgfile

    if imgfile == ""
	call inputsave()
	let imgfile = input("Image file: ", '', 'file')
	call inputrestore()
    endif

    if imgfile == ""
	redraw
	echohl WarningMsg
	echo "No image file provided. Not posted to Friendfeed."
	echohl None
	return
    endif

    call s:prompt_ffeed(a:mesg, imgfile)
endfunction


" Prompt user for Friendfeed message or take message from command line.
if !exists(":PostFfeed")
    command -nargs=? PostFfeed :call <SID>prompt_ffeed(<q-args>, '')
endif

" Post current line to Friendfeed.
if !exists(":CPostFfeed")
    command -range CPostFfeed :call <SID>post_ffeed(join(getline(<line1>,<line2>), ' '), '')
endif

" Post visual selection to Friendfeed.
noremap <SID>Visual y:call <SID>post_ffeed(@", '')<cr>
noremap <unique> <script> <Plug>FfeedVisual <SID>Visual
if !hasmapto('<Plug>FfeedVisual')
    vmap <unique> <Leader>f <Plug>FfeedVisual
endif

" Prompt user for Friendfeed image file name or get it from command line.
if !exists(":PostImageFfeed")
    command -complete=file -nargs=? PostImageFfeed :call <SID>prompt_image_ffeed('', <q-args>)
endif

" Post current line to Friendfeed but prompt user for Friendfeed image file
" name or get it from command line.
if !exists(":CPostImageFfeed")
    command -range -complete=file -nargs=? CPostImageFfeed :call <SID>prompt_image_ffeed(join(getline(<line1>,<line2>), ' '), <q-args>)
endif

" Post visual selection to Friendfeed with prompt for image file.
noremap <SID>ImageVisual y:call <SID>prompt_image_ffeed(@", '')<cr>
noremap <unique> <script> <Plug>FfeedImageVisual <SID>ImageVisual
if !hasmapto('<Plug>FfeedImageVisual')
    vmap <unique> <Leader>F <Plug>FfeedImageVisual
endif

let &cpo = s:save_cpo
finish

" vim:set tw=0:
