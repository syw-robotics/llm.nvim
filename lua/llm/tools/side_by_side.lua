local M = {}
local Layout = require("nui.layout")
local conf = require("llm.config")
local LOG = require("llm.common.log")

function M.handler(name, F, state, streaming, prompt, opts)
  local ft = vim.bo.filetype
  if prompt == nil then
    prompt = require("llm.tools.prompts").side_by_side
  elseif type(prompt) == "function" then
    prompt = prompt()
  end

  local source_content = F.GetVisualSelection()

  local options = {
    _name = "side_by_side",
    left = {
      title = " Source ",
      focusable = false,
    },
    right = {
      title = " Preview ",
      focusable = true,
      enter = true,
    },
    buftype = "nofile",
    spell = false,
    number = true,
    wrap = true,
    linebreak = false,
    timeout = 30,
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
  options.fetch_key = options.fetch_key and options.fetch_key or conf.configs.fetch_key

  local source_box = F.CreatePopup(options.left.title, false, options.left)
  local preview_box = F.CreatePopup(options.right.title, true, options.right)

  local layout = F.CreateLayout(
    "80%",
    "55%",
    Layout.Box({
      Layout.Box(source_box, { size = "50%" }),
      Layout.Box(preview_box, { size = "50%" }),
    }, { dir = "row" })
  )

  layout:mount()

  F.SetBoxOpts({ source_box, preview_box }, {
    filetype = { ft, ft },
    buftype = options.buftype,
    spell = options.spell,
    number = options.number,
    wrap = options.wrap,
    linebreak = options.linebreak,
  })

  state.popwin = source_box
  F.WriteContent(source_box.bufnr, source_box.winid, source_content)

  state.app["session"][name] = {
    { role = "system", content = prompt },
    { role = "user", content = source_content },
  }
  options.messages = state.app["session"][name]
  options.bufnr = preview_box.bufnr
  options.winid = preview_box.winid

  state.popwin = preview_box
  streaming(options)

  preview_box:map("n", "<C-c>", F.CancelLLM)

  local default_actions = {
    accept = function()
      vim.api.nvim_set_current_win(preview_box.winid)
      vim.api.nvim_command("normal! ggVGky")
    end,
    reject = function() end,
    close = function() end,
  }
  for _, v in ipairs({ source_box, preview_box }) do
    for _, k in ipairs({ "accept", "reject", "close" }) do
      v:map(options[k].mapping.mode, options[k].mapping.keys, function()
        F.CancelLLM()
        if options[k].action ~= nil then
          options[k].action()
        else
          default_actions[k]()
        end
        layout:unmount()
      end)
    end
  end
end

return M
