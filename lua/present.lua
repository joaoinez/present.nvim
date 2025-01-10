local M = {}

function M.setup()
  --
end

function M.create_floating_window(win_config, enter)
  enter = enter or false
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, enter, win_config)

  return { buf = buf, win = win }
end

---@class present.Slides
---@field slides present.Slide[]: The slides of the file

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide
---@field blocks present.Block[]: Codeblocks inside of a slide

---@class present.Block
---@field language string: The language of the codeblock
---@field body string: The body of the codeblock

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local function parse_slides(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = '',
    body = {},
    blocks = {},
  }
  for _, line in ipairs(lines) do
    if line:find '^#' then
      if #current_slide.title > 0 then table.insert(slides.slides, current_slide) end

      current_slide = {
        title = line,
        body = {},
        blocks = {},
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  for _, slide in ipairs(slides.slides) do
    local block = {
      language = nil,
      body = '',
    }
    local inside_block = false
    for _, line in ipairs(slide.body) do
      if vim.startswith(line, '```') then
        if not inside_block then
          inside_block = true
          block.language = string.sub(line, 4)
        else
          inside_block = false
          block.body = vim.trim(block.body)
          table.insert(slide.blocks, block)
        end
      else
        if inside_block then block.body = block.body .. line .. '\n' end
      end
    end
  end

  return slides
end

local function create_windows_configs()
  local width = vim.o.columns
  local height = vim.o.lines
  local header_height = 1 + 2 + 2
  local footer_height = 1
  local body_height = height - header_height - footer_height - 2

  return {
    header = {
      relative = 'editor',
      width = width,
      height = 3,
      col = 0,
      row = 0,
      style = 'minimal',
      border = 'rounded',
    },
    body = {
      relative = 'editor',
      width = width,
      height = body_height,
      col = 0,
      row = 5,
      style = 'minimal',
      border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
    },
    footer = {
      relative = 'editor',
      width = width,
      height = 1,
      col = 0,
      row = height - 1,
      style = 'minimal',
    },
  }
end

local state = {
  title = '',
  parsed = {},
  current_slide = 1,
  floats = {},
}

local function foreach_float(cb)
  for name, float in pairs(state.floats) do
    cb(name, float)
  end
end

local function present_keymap(mode, key, callback)
  vim.keymap.set(mode, key, callback, { buffer = state.floats.body.buf })
end

function M.start_presenting(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0
  local windows = create_windows_configs()
  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)

  state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ':t')
  state.parsed = parse_slides(lines)
  state.floats.header = M.create_floating_window(windows.header)
  state.floats.body = M.create_floating_window(windows.body, true)
  state.floats.footer = M.create_floating_window(windows.footer)

  local set_slide_content = function(index)
    local slide = state.parsed.slides[index]
    local title_padding = string.rep(' ', (vim.o.columns - #slide.title) / 2)
    local title = title_padding .. slide.title
    local footer = string.format(
      ' %d / %d | %s --- n: next | p: previous | x: execute | q: quit',
      state.current_slide,
      #state.parsed.slides,
      state.title
    )
    local footer_padding = string.rep(' ', (vim.o.columns - #footer) / 2)
    local padded_footer = { footer_padding .. footer }

    vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { '', title, '' })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)
    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, padded_footer)
  end

  foreach_float(function(_, float) vim.bo[float.buf].filetype = 'markdown' end)

  present_keymap('n', 'n', function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  present_keymap('n', 'p', function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  present_keymap('n', 'q', function() vim.api.nvim_win_close(state.floats.body.win, true) end)

  present_keymap('n', 'x', function()
    local slide = state.parsed.slides[state.current_slide]
    local block = slide.blocks[1]

    if not block then
      print 'No blocks on this slide'
      return
    end

    local original_print = print

    local output = { '', '```' .. block.language }
    vim.list_extend(output, vim.split(block.body, '\n'))
    vim.list_extend(output, { '```' })

    print = function(...)
      local args = { ... }
      local message = table.concat(vim.tbl_map(tostring, args), '\t')

      table.insert(output, message)
    end

    local chunk = loadstring(block.body)

    pcall(function()
      table.insert(output, '')
      table.insert(output, '#### Output ')
      table.insert(output, '')

      if not chunk then
        table.insert(output, '<<<BROKEN CODE>>>')
      else
        chunk()
      end
    end)

    print = original_print

    local buf = vim.api.nvim_create_buf(false, true)
    local temp_width = math.floor(vim.o.columns * 0.33)
    local temp_height = math.floor(vim.o.lines * 0.33)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      style = 'minimal',
      noautocmd = true,
      width = temp_width,
      height = temp_height,
      row = math.floor((vim.o.lines - temp_height) / 2),
      col = math.floor((vim.o.columns - temp_width) / 2),
      border = 'rounded',
      title = 'Codeblock',
    })

    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0,
    },
  }

  for option, config in pairs(restore) do
    vim.o[option] = config.present
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = state.floats.body.buf,
    callback = function()
      for option, config in pairs(restore) do
        vim.o[option] = config.original
      end

      foreach_float(function(_, float) pcall(vim.api.nvim_win_close, float.win, true) end)
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = vim.api.nvim_create_augroup('present_resized', {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then return end

      local updated = create_windows_configs()

      foreach_float(function(name, float) vim.api.nvim_win_set_config(float.win, updated[name]) end)

      set_slide_content(state.current_slide)
    end,
  })

  set_slide_content(state.current_slide)
end

M._parse_slides = parse_slides

return M
