local LOG = require("llm.common.log")
local utils = require("llm.tools.utils")
local diff = require("llm.common.diff_style")
local parse = require("llm.common.io.parse")
local conf = require("llm.config")
local Split = require("nui.split")

local M = {}

function M.handler(name, F, state, streaming, prompt, opts)
  if diff.style == nil then
    diff = diff:update()
  end

  local options = {
    _name = "Action",
    separator = "─",
    start_str = "```",
    end_str = "```",
    only_display_diff = false,
    enable_buffer_context = true,
    language = "English",
    templates = nil,
    url = nil,
    model = nil,
    api_type = nil,
    args = nil,
    parse_handler = nil,
    stdout_handler = nil,
    stderr_handler = nil,
    timeout = 30,
    input = {
      buftype = "nofile",
      relative = "win",
      position = "bottom",
      size = "25%",
      enter = true,
      spell = false,
      number = false,
      relativenumber = false,
      wrap = true,
      linebreak = false,
      signcolumn = "no",
    },
    output = {
      buftype = "nofile",
      relative = "editor",
      position = "right",
      size = "25%",
      enter = true,
      spell = false,
      number = false,
      relativenumber = false,
      wrap = true,
      linebreak = false,
      signcolumn = "no",
    },
    accept = {
      mapping = {
        mode = "n",
        keys = { "Y", "y" },
      },
      action = nil,
    },
    reject = {
      mapping = {
        mode = "n",
        keys = { "N", "n" },
      },
      action = nil,
    },
    close = {
      mapping = {
        mode = "n",
        keys = { "<esc>" },
      },
      action = nil,
    },
  }

  options = vim.tbl_deep_extend("force", options, opts or {})

  if prompt == nil then
    prompt = string.format(require("llm.tools.prompts").action, options.language)
  elseif type(prompt) == "function" then
    prompt = prompt()
  end

  local ft = F.GetFileType()
  if options.templates and options.templates[ft] then
    prompt = prompt .. string.format("\n\n%s", options.templates[ft])
  end
  options.fetch_key = options.fetch_key and options.fetch_key or conf.configs.fetch_key

  local bufnr = vim.api.nvim_get_current_buf()
  local winnr = vim.api.nvim_get_current_win()
  local cursor_pos = vim.api.nvim_win_get_cursor(winnr)
  local mode = options.mode or vim.fn.mode()
  local lines, start_line, start_col, end_line, end_col =
    F.GetVisualSelectionRange(bufnr, mode, options.enable_buffer_context)
  local source_content = F.GetVisualSelection(lines)

  F.VisMode2NorMode()

  local context = {
    bufnr = bufnr,
    filetype = F.GetFileType(bufnr),
    contents = lines,
    winnr = winnr,
    cursor_pos = cursor_pos,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }

  state.app["session"][name] = {
    { role = "system", content = prompt },
    { role = "user", content = source_content },
  }
  options.messages = state.app.session[name]
  local default_actions = {}
  if options.only_display_diff then
    default_actions = {
      accept = function()
        if diff and diff.valid then
          diff:accept()
        end
      end,
      reject = function()
        if diff and diff.valid then
          diff:reject()
        end
      end,
      close = function()
        if diff and diff.valid then
          diff:reject()
        end
      end,
    }
    options.exit_handler = function(ostr)
      utils.new_diff(diff, options, context, ostr)
    end

    parse.GetOutput(options)
  else
    local preview_box = Split({
      relative = options.output.relative,
      position = options.output.position,
      size = options.output.size,
      enter = options.output.enter,
      buf_options = {
        filetype = "llm",
        buftype = options.output.buftype,
      },
      win_options = {
        spell = options.output.spell,
        number = options.output.number,
        relativenumber = options.output.relativenumber,
        wrap = options.output.wrap,
        linebreak = options.output.linebreak,
        signcolumn = options.output.signcolumn,
      },
    })

    preview_box:mount()

    state.popwin = preview_box

    local input_box = Split({
      relative = options.input.relative,
      position = options.input.position,
      size = options.input.size,
      enter = options.input.enter,
      buf_options = {
        filetype = "llm",
        buftype = options.input.buftype,
      },
      win_options = {
        spell = options.input.spell,
        number = options.input.number,
        relativenumber = options.input.relativenumber,
        wrap = options.input.wrap,
        linebreak = options.input.linebreak,
        signcolumn = options.input.signcolumn,
      },
    })
    utils.single_turn_dialogue(preview_box, streaming, options, context, diff)

    preview_box:map("n", "<C-c>", F.CancelLLM)

    default_actions = {
      accept = function()
        if diff and diff.valid then
          diff:accept()
        end
      end,
      reject = function()
        if diff and diff.valid then
          diff:reject()
        end
      end,
      close = function()
        F.CancelLLM()
        if diff and diff.valid then
          diff:reject()
        end
        preview_box:unmount()
      end,
    }

    preview_box:map(options.close.mapping.mode, options.close.mapping.keys, function()
      default_actions.close()
      if options.close.action ~= nil then
        options.close.action()
      end
      for _, kk in ipairs({ "accept", "reject", "close" }) do
        utils.clear_keymapping(options[kk].mapping.mode, options[kk].mapping.keys, bufnr)
      end
    end)

    preview_box:map("n", { "I", "i" }, function()
      input_box:mount()
      if diff and diff.valid then
        diff:reject()
      end
      vim.api.nvim_command("startinsert")
      input_box:map("n", { "<esc>" }, function()
        input_box:unmount()
      end)

      input_box:map("n", { "<CR>" }, function()
        local contents = vim.api.nvim_buf_get_lines(input_box.bufnr, 0, -1, true)
        table.remove(state.app.session[name], #state.app.session[name])
        state.app.session[name][1].content = state.app.session[name][1].content .. "\n" .. table.concat(contents, "\n")
        vim.api.nvim_buf_set_lines(input_box.bufnr, 0, -1, false, {})
        utils.single_turn_dialogue(preview_box, streaming, options, context, diff)
      end)
    end)

    preview_box:map("n", { "<C-r>" }, function()
      if diff and diff.valid then
        diff:reject()
      end
      table.remove(state.app.session[name], #state.app.session[name])
      utils.single_turn_dialogue(preview_box, streaming, options, context, diff)
    end)
  end

  for _, k in ipairs({ "accept", "reject", "close" }) do
    utils.set_keymapping(options[k].mapping.mode, options[k].mapping.keys, function()
      default_actions[k]()
      if options[k].action ~= nil then
        options[k].action()
      end
      if k == "close" then
        for _, kk in ipairs({ "accept", "reject", "close" }) do
          utils.clear_keymapping(options[kk].mapping.mode, options[kk].mapping.keys, bufnr)
        end
      end
    end, bufnr)
  end
end
return M
