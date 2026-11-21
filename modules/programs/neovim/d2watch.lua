-- lua/d2watch.lua
-- Live high-fidelity D2 preview: d2 --watch in WSL, opened in a Windows browser via WSL interop.
-- Landed via nixcfg nixvim extraFiles. Keep d2_args in sync with the d2-animator skill.
local M = {}
local api, uv = vim.api, (vim.uv or vim.loop)

M.config = {
  host = "127.0.0.1",          -- d2 --host. "0.0.0.0" listens on all interfaces.
  port = 8787,                 -- base port. 0 = let d2 choose (URL is read from d2's log).
  port_search = 20,            -- try port .. port+N to find a free one (one watcher per buffer)
  browser = "edge",            -- "edge" | "firefox" | "default" (Windows default browser)
  edge_app_window = true,      -- Edge --app=<url>: chromeless window you can snap beside the terminal
  edge_path = nil,             -- override auto-detected msedge.exe path
  firefox_path = nil,          -- override auto-detected firefox.exe path
  autostart = true,            -- start watching when a .d2 buffer is opened
  autoopen = true,             -- open the browser once the server is reachable
  open_timeout_ms = 8000,
  out_dir = vim.fn.stdpath("cache") .. "/d2watch",
  d2 = "d2",
  d2_args = { "--theme", "200", "--dark-theme", "200", "--layout", "elk", "--pad", "40" },
}

local watchers = {}   -- bufnr -> { job=, port=, url=, log={} }

local function notify(msg, lvl) vim.notify(msg, lvl or vim.log.levels.INFO, { title = "d2watch" }) end

local function first_exe(paths)
  for _, p in ipairs(paths) do if p and vim.fn.executable(p) == 1 then return p end end
end

local function browser_cmd(url)
  local c = M.config
  if c.browser == "edge" then
    local exe = first_exe({ c.edge_path,
      "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
      "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" })
    if exe then return { exe, c.edge_app_window and ("--app=" .. url) or url } end
  elseif c.browser == "firefox" then
    local exe = first_exe({ c.firefox_path, "/mnt/c/Program Files/Mozilla Firefox/firefox.exe",
      "/mnt/c/Program Files (x86)/Mozilla Firefox/firefox.exe" })
    if exe then return { exe, "--new-window", url } end   -- Firefox has no --app mode
  end
  return { "cmd.exe", "/c", "start", "", url }            -- fallback: Windows default browser
end

local function browse_host()
  local h = M.config.host
  if h == "0.0.0.0" or h == "" or h == "::" then return "localhost" end
  if h == "127.0.0.1" then return "localhost" end
  return h
end

local function port_free(port)
  local tcp = uv.new_tcp()
  local ok = tcp:bind(M.config.host == "localhost" and "127.0.0.1" or M.config.host, port)
  tcp:close()
  return ok ~= nil
end

local function used_ports()
  local s = {}
  for _, w in pairs(watchers) do if w.port then s[w.port] = true end end
  return s
end

local function pick_port()
  local c = M.config
  if c.port == 0 then return 0 end
  local used = used_ports()
  for p = c.port, c.port + c.port_search do
    if not used[p] and port_free(p) then return p end
  end
  error(("d2watch: no free port in %d-%d"):format(c.port, c.port + c.port_search))
end

local function open_url(url)
  vim.fn.jobstart(browser_cmd(url), { cwd = "/mnt/c", detach = true })
end

-- Poll until the server accepts TCP connections, then open the browser.
local function open_when_ready(w)
  local deadline = uv.now() + M.config.open_timeout_ms
  local timer = uv.new_timer()
  timer:start(0, 200, function()
    if not w.port then return end   -- port=0: wait for the URL to appear in the log
    if uv.now() > deadline then
      timer:stop(); timer:close()
      vim.schedule(function() notify("server not reachable on port " .. w.port, vim.log.levels.WARN) end)
      return
    end
    local tcp = uv.new_tcp()
    tcp:connect("127.0.0.1", w.port, function(err)
      tcp:close()
      if not err and not timer:is_closing() then
        timer:stop(); timer:close()
        vim.schedule(function() open_url(w.url) end)
      end
    end)
  end)
end

function M.start(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
  if watchers[bufnr] then return M.open(bufnr) end
  local c, file = M.config, api.nvim_buf_get_name(bufnr)
  if file == "" or not file:match("%.d2$") then return notify("not a .d2 buffer", vim.log.levels.WARN) end

  local port = pick_port()
  vim.fn.mkdir(c.out_dir, "p")
  local out = c.out_dir .. "/" .. vim.fn.fnamemodify(file, ":t:r") .. ".svg"
  local cmd = { c.d2, "--watch", "--browser", "0", "--host", c.host, "--port", tostring(port) }
  vim.list_extend(cmd, c.d2_args)
  vim.list_extend(cmd, { file, out })

  local w = { port = port ~= 0 and port or nil, log = {} }
  w.url = w.port and ("http://%s:%d"):format(browse_host(), port) or nil
  local function on_out(_, data)
    for _, line in ipairs(data or {}) do
      if line ~= "" then
        table.insert(w.log, line)
        if not w.port then   -- port=0: learn the URL from d2's output
          local h, p = line:match("https?://([%w%.%-%[%]:]-):(%d+)")
          if p then w.port = tonumber(p); w.url = ("http://%s:%s"):format(browse_host(), p) end
        end
      end
    end
  end
  w.job = vim.fn.jobstart(cmd, {
    cwd = vim.fn.fnamemodify(file, ":h"),   -- relative imports/icons resolve from the file's dir
    on_stdout = on_out, on_stderr = on_out,
    on_exit = function(_, code)
      watchers[bufnr] = nil
      if code ~= 0 and code ~= 143 then
        vim.schedule(function() notify("d2 --watch exited (" .. code .. "); see :D2WatchLog", vim.log.levels.WARN) end)
      end
    end,
  })
  if w.job <= 0 then return notify("failed to start d2 (is it on PATH?)", vim.log.levels.ERROR) end
  watchers[bufnr] = w
  notify(("watching %s on %s"):format(vim.fn.fnamemodify(file, ":t"), w.url or "auto port"))
  if c.autoopen then open_when_ready(w) end
end

function M.stop(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
  local w = watchers[bufnr]
  if w then vim.fn.jobstop(w.job); watchers[bufnr] = nil end
end

function M.open(bufnr)
  local w = watchers[(bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr]
  if not w or not w.url then return notify("no running watch for this buffer", vim.log.levels.WARN) end
  open_url(w.url)
end

function M.toggle() if watchers[api.nvim_get_current_buf()] then M.stop() else M.start() end end

function M.log()
  local w = watchers[api.nvim_get_current_buf()]
  vim.cmd("botright new"); vim.bo.buftype = "nofile"; vim.bo.bufhidden = "wipe"
  api.nvim_buf_set_lines(0, 0, -1, false, w and w.log or { "(no running watch for that buffer)" })
end

function M.status()
  local lines = {}
  for b, w in pairs(watchers) do
    table.insert(lines, ("%s -> %s"):format(vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t"), w.url or "?"))
  end
  notify(#lines > 0 and table.concat(lines, "\n") or "no watchers")
end

-- Prompt for the browser (edge|firefox|default) without needing :D2WatchBrowser <arg>.
function M.choose_browser()
  vim.ui.select({ "edge", "firefox", "default" }, { prompt = "D2 browser:" }, function(choice)
    if choice then M.config.browser = choice; notify("browser = " .. choice) end
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  -- Allow per-shell overrides without editing config.
  if vim.env.D2WATCH_PORT then M.config.port = tonumber(vim.env.D2WATCH_PORT) end
  if vim.env.D2WATCH_HOST then M.config.host = vim.env.D2WATCH_HOST end
  if vim.env.D2WATCH_BROWSER then M.config.browser = vim.env.D2WATCH_BROWSER end

  vim.filetype.add({ extension = { d2 = "d2" } })
  local g = api.nvim_create_augroup("d2watch", { clear = true })
  if M.config.autostart then
    -- FileType (not BufReadPost) so autostart fires in every way a .d2 buffer
    -- appears: opening an existing file, `nvim new.d2` on a not-yet-existing
    -- file, and saving a scratch buffer with `:w foo.d2`. BufReadPost only
    -- covers the first. M.start no-ops on a buffer it already watches.
    api.nvim_create_autocmd("FileType", { group = g, pattern = "d2",
      callback = function(ev) M.start(ev.buf) end })
  end
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, { group = g, pattern = "*.d2",
    callback = function(ev) M.stop(ev.buf) end })
  api.nvim_create_autocmd("VimLeavePre", { group = g,
    callback = function() for b in pairs(watchers) do M.stop(b) end end })

  -- Commands carry desc so they're self-documenting in :-completion and which-key.
  local cmd = api.nvim_create_user_command
  cmd("D2WatchStart",  function() M.start()  end, { desc = "D2: start watching this .d2 buffer" })
  cmd("D2WatchStop",   function() M.stop()   end, { desc = "D2: stop watching this buffer" })
  cmd("D2WatchToggle", function() M.toggle() end, { desc = "D2: toggle watch for this buffer" })
  cmd("D2WatchOpen",   function() M.open()   end, { desc = "D2: open/refresh the diagram in the browser" })
  cmd("D2WatchLog",    function() M.log()    end, { desc = "D2: show this watcher's d2 log" })
  cmd("D2WatchStatus", function() M.status() end, { desc = "D2: list active watchers and URLs" })
  cmd("D2WatchBrowser", function(o) M.config.browser = o.args; notify("browser = " .. o.args) end,
    { nargs = 1, desc = "D2: set browser (edge|firefox|default)",
      complete = function() return { "edge", "firefox", "default" } end })

  -- Buffer-local keymaps under <leader>D ("D2 diagram" group in which-key), set only in
  -- .d2 buffers so they never clutter the global <leader>d (Diff/Git) namespace. desc is
  -- read by which-key for the per-key menu when <leader>D is pressed in a .d2 buffer.
  api.nvim_create_autocmd("FileType", { group = g, pattern = "d2",
    callback = function(ev)
      local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
      end
      map("<leader>Dw", M.toggle,         "Toggle watch")
      map("<leader>Do", M.open,           "Open/refresh in browser")
      map("<leader>Ds", M.status,         "Status (list watchers)")
      map("<leader>Dx", M.stop,           "Stop watch")
      map("<leader>Dl", M.log,            "Watch log")
      map("<leader>Db", M.choose_browser, "Switch browser (edge/firefox)")
    end })
end

return M
