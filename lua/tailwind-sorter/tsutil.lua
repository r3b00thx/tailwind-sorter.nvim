local parsers = require("nvim-treesitter.parsers")

local util = require("tailwind-sorter.util")

local M = {}

--- @class TWRange
--- @field start_row integer
--- @field start_col integer
--- @field end_row integer
--- @field end_col integer
--- @endclass

--- @class TWMatch
--- @field buf integer
--- @field node userdata
--- @field offset nil|TWRange
--- @endclass

--- @param match TWMatch
--- @return string
M.get_match_text = function(match)
  if not match or not match.node or not match.buf then
    vim.notify("Invalid match passed to get_match_text", vim.log.levels.WARN)
    return ""
  end

  local ok, text = pcall(vim.treesitter.get_node_text, match.node, match.buf)
  if not ok then
    vim.notify("Failed to get node text: " .. text, vim.log.levels.ERROR)
    return ""
  end

  if match.offset then
    text = text:sub(match.offset.start_col, match.offset.end_col)
  end

  return text
end

--- @param match TWMatch
--- @param text string
M.replace_match_text = function(match, text)
  local original = vim.treesitter.get_node_text(match.node, match.buf)

  local parts = vim.split(original, M.get_match_text(match), { plain = true })

  local tmp = parts[2]
  parts[2] = text
  parts[3] = tmp

  return table.concat(parts, "")
end

--- @param match TWMatch
--- @param text string
M.put_new_node_text = function(match, text)
  local original = M.get_match_text(match)
  text = M.replace_match_text(match, text)

  if original == text then
    return
  end

  local lines = util.split_lines(text)
  local srow, scol, erow, ecol = match.node:range()

  vim.api.nvim_buf_set_text(match.buf, srow, scol, erow, ecol, lines)
end

--- @param buf integer
--- @return TWMatch[]
M.get_query_matches = function(buf)
  local bufnr = buf or vim.api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr)
  local matches = {}

  if parser then
    parser:for_each_tree(function(tree, lang_tree)
      local lang = lang_tree:lang()

      local query = M.get_query(lang, "tailwind")
      if not query then
        return
      end

      for pattern, match, _ in query:iter_matches(tree:root(), buf, 0, -1) do
        if match then
          for id, node in pairs(match) do
            if query.captures[id] == "tailwind" then
              local res = { node = node, buf = buf }

              if query.info.patterns[pattern] then
                for _, pred in pairs(query.info.patterns[pattern]) do
                  if pred[2] == id and pred[1] == "offset!" then
                    res.offset = {
                      start_row = tonumber(pred[3]),
                      start_col = tonumber(pred[4]),
                      end_row = tonumber(pred[5]),
                      end_col = tonumber(pred[6]),
                    }
                  end
                end
              end

              table.insert(matches, res)
            end
          end
        end
      end
    end)
  end

  return matches
end

--- @param lang string
--- @param query string
M.get_query = function(lang, query)
  -- vim.treesitter.query.get for nightly.
  if vim.treesitter.query.get ~= nil then
    return vim.treesitter.query.get(lang, query)
  else
    -- vim.treesitter.get_query for stable.
    return vim.treesitter.query.get_query(lang, query)
  end
end

return M
