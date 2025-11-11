vim9script

# TeXpresso plugin for Vim9

# Configuration
if !exists("g:texpresso_path")
  g:texpresso_path = "texpresso"
endif

# Logging
var Logger: func = null_function

# Cache last arguments
var last_args: list<string> = []

# TeXpresso process state
var job_queued: string = null_string
var job_process: job = null_job
var job_needs_resync: bool = false

# Log output and problems
var log: list<string> = []
var fix: list<dict<any>> = []
var fixcursor: number = 0

# Log buffer ID
var log_buffer_id: number = -1

# SyncTeX state
var skip_synctex: bool = false
var last_line: number = -1
var last_file: string = ""

# Quickfix ID
var qfid: number = -1

# Get or create log buffer
def LogBuffer(): number
  if !bufexists(log_buffer_id)
    for buf in getbufinfo()
      if buf.name ==# "texpresso-log"
        log_buffer_id = buf.bufnr
        break
      endif
    endfor
  endif

  if !bufexists(log_buffer_id)
    log_buffer_id = bufadd("texpresso-log")
    setbufvar(log_buffer_id, '&buftype', 'nofile')
    setbufvar(log_buffer_id, '&swapfile', 0)
  endif

  return log_buffer_id
enddef

# Append lines to buffer
def BufferAppend(buf: number, lines: list<string>)
  var lastline = getbufline(buf, '$')
  if empty(lastline)
    lastline = ['']
  endif
  lines[0] = lastline[0] .. lines[0]
  setbufline(buf, '$', lines[0])
  if len(lines) > 1
    appendbufline(buf, '$', lines[1 : ])
  endif
  if line('$', buf) > 8000
    deletebufline(buf, 1, 4000)
  endif
enddef

# Convert HEX color to RGB values
def HexToRgb(hex: string): list<float>
  var cleanHex = hex->trim()

  # Remove '#' prefix if present
  if cleanHex[0] == '#'
    cleanHex = cleanHex[1 : ]
  endif

  # Validate hex string (must be 6 characters)
  if cleanHex->len() != 6 || cleanHex !~ '^[0-9a-fA-F]\{6}$'
    echoerr $"Invalid HEX color: {hex}"
    return []
  endif

  # Extract and convert RGB components
  var r = str2nr(cleanHex[0 : 1], 16)
  var g = str2nr(cleanHex[2 : 3], 16)
  var b = str2nr(cleanHex[4 : 5], 16)

  return [r / 255.0, g / 255.0, b / 255.0]
enddef

# SyncTeX backward search
def SynctexBackward(file: string, line: number)
  skip_synctex = true
  try
    execute $'buffer +{line - 1} {file}'
  catch
    execute $'edit +{line - 1} {file}'
  endtry
enddef

# Get or create quickfix ID
def GetQfId(): number
  var info = getqflist({id: qfid})
  if info.id > 0
    return info.id
  endif
  setqflist([], ' ', {title: "TeXpresso"})
  return getqflist({id: 0}).id
enddef

# Set quickfix items
def SetQf(items: list<dict<any>>)
  qfid = GetQfId()
  setqflist([], 'r', {id: qfid, items: items})
enddef

# Parse Tectonic diagnostic line
def FormatFix(line: string): dict<any>
  var match = matchlist(line, '\([a-z]\+\): \(.*\):\(\d*\): \(.*\)')
  if !empty(match)
    var txt = match[4]
    if txt =~# '^Overfull' || txt =~# '^Underfull'
      return {}
    endif
    return {
      type: match[1],
      filename: match[2],
      lnum: str2nr(match[3]),
      text: txt
    }
  else
    return {text: line}
  endif
enddef

# Shrink list to count elements
def Shrink(tbl: list<any>, count: number)
  while len(tbl) > count
    remove(tbl, -1)
  endwhile
enddef

# Expand list to count elements
def Expand(tbl: list<any>, count: number, default: any)
  while len(tbl) < count
    add(tbl, default)
  endwhile
enddef

# Process message from TeXpresso
def ProcessMessage(json: list<any>)
  var msg = json[0]

  if msg ==# "reset-sync"
    job_needs_resync = true
  elseif msg ==# "synctex"
    timer_start(0, (_) => SynctexBackward(json[1], json[2]))
  elseif msg ==# "truncate-lines"
    var name = json[1]
    var count = json[2]
    if name ==# "log"
      Shrink(log, count)
      Expand(log, count, "")
    elseif name ==# "out"
      Expand(fix, count, {})
      fixcursor = count
    endif
  elseif msg ==# "append-lines"
    var name = json[1]
    if name ==# "log"
      for i in range(2, len(json) - 1)
        add(log, json[i])
      endfor
    elseif name ==# "out"
      for i in range(2, len(json) - 1)
        fixcursor += 1
        fix[fixcursor - 1] = FormatFix(json[i])
      endfor
      timer_start(0, (_) => SetQf(fix))
    endif
  elseif msg ==# "flush"
    Shrink(fix, fixcursor)
    timer_start(0, (_) => SetQf(fix))
  endif
enddef

# Send command to TeXpresso
def Send(...args: list<any>)
  var text = json_encode(args)
  if job_process != null_job
    ch_sendraw(job_process, text .. "\n")
  endif
enddef

# Reload buffer in TeXpresso
export def Reload(buf: number)
  var path = fnamemodify(bufname(buf), ":p")
  Send("open", path, BufferGetLines(buf, 0, -1))
enddef

# Communicate changed lines
def ChangeLines(buf: number, index: number, count: number, last: number)
  if job_needs_resync
    Reload(buf)
	job_needs_resync = false
  else
    var path = fnamemodify(bufname(buf), ":p")
    var lines = BufferGetLines(buf, index, last)
    Send("change-lines", path, index, count, lines)
  endif
enddef

# Get buffer lines as string
def BufferGetLines(buf: number, first: number, last: number): string
  if first == last
    return ""
  else
    var lines = getbufline(buf, first, last == -1 ? '$' : last)
    return join(lines, "\n") .. "\n"
  endif
enddef

# Attach buffer synchronization
def Attach(buf: number)
  Reload(buf)
  augroup TeXpressoBuffer
    au!
    execute $"autocmd TextChanged <buffer={buf}> Reload({buf})"
    execute $"autocmd TextChangedI <buffer={buf}> ChangeLines({buf}, line('.'), 2, line('.') + 1)"
    execute $"autocmd BufUnload <buffer={buf}> Send('close', bufname({buf}))"
  augroup END
enddef

# Apply VIM theme to TeXpresso
def Theme()
  var colors = hlget('Normal', true)
  if !empty(colors) && has_key(colors[0], 'guibg') && has_key(colors[0], 'guifg')
    var bg = HexToRgb(colors[0].guibg)
    var fg = HexToRgb(colors[0].guifg)
    Send("theme", bg, fg)
  endif
enddef

def SynctexForwardHook()
  if skip_synctex
    skip_synctex = false
    return
  endif

  var pos = getcurpos()
  var line = pos[1]
  var file = expand('%:p')

  if last_line == line && last_file ==# file
    return
  endif

  last_line = line
  last_file = file
  Send("synctex-forward", file, line)
enddef

# Launch TeXpresso viewer
export def Launch(...args: list<string>)
  if job_process != null_job
    job_stop(job_process)
  endif

  var cmd = [g:texpresso_path, "-json", "-lines"]

  var use_args = empty(args) ? last_args : args
  # last arg should be filename, expand it to full path
  use_args[-1] = fnamemodify(expand(use_args[-1]), ":p")
  if empty(use_args)
    echo "No root file specified, use e.g. :TeXpresso main.tex"
    return
  endif

  last_args = use_args
  cmd += use_args

  job_queued = ""
  job_process = job_start(cmd, {
    out_cb: (channel, msg) => {
      var new_msg = msg
      if job_queued != null_string
        new_msg = job_queued .. msg
      endif

      try
        var data = json_decode(new_msg)
        ProcessMessage(data)
        job_queued = ""
      catch
        job_queued = new_msg
      endtry
    },
    err_cb: (channel, msg) => {
      var buf = LogBuffer()
      BufferAppend(buf, [msg])
    },
    exit_cb: (job, status) => {
      job_process = null_job
    }
  })

  Theme()
  Attach(bufnr())
enddef

# Setup autocommands
augroup TeXpresso
  autocmd!
  autocmd ColorScheme * Theme()
  autocmd CursorMoved *.tex SynctexForwardHook()
augroup END
# vim: ts=2 sts=2 sw=2
