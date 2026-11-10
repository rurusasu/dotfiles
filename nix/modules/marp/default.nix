{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.marp;
  json = pkgs.formats.json { };
  configFile = json.generate "marp-config.json" cfg.settings;
  marp = pkgs.writeShellApplication {
    name = "marp";
    text = ''
      exec ${lib.getExe cfg.package} --config ${configFile} "$@"
    '';
  };
  preview = pkgs.writeShellApplication {
    name = "marp-preview";
    text = ''
      export PORT=${toString cfg.preview.port}
      exec ${lib.getExe marp} --server --watch "$@"
    '';
  };
  terminalCommand = action: fallback: ''
    function()
        for _, terminal in ipairs(Snacks.terminal.list()) do
            if type(terminal.cmd) == "table" and terminal.cmd[1] == ${builtins.toJSON (lib.getExe preview)} then
                local job = vim.b[terminal.buf].terminal_job_id
                if vim.fn.jobwait({ job }, 0)[1] == -1 then
                    ${action}
                    return
                end
                terminal:close()
            end
        end
        ${fallback}
    end
  '';
in
{
  options.programs.marp = {
    enable = lib.mkEnableOption "Marp CLI and slide preview";
    package = lib.mkPackageOption pkgs "marp-cli" { };
    settings = lib.mkOption {
      inherit (json) type;
      default = {
        theme = "default";
      };
      description = "Shared Marp configuration used by marp and marp-preview.";
    };
    preview.port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port of the Marp preview server.";
    };
  };

  config = lib.mkMerge [
    { programs.marp.enable = true; }
    (lib.mkIf cfg.enable {
      home.packages = [
        marp
        preview
      ];
      xdg.configFile."marp/config.json".source = configFile;

      programs.nixvim = { config, ... }: {
        config = lib.mkIf config.enable {
          keymaps = [
            {
              mode = "n";
              key = "<leader>marp";
              action = "<cmd>MarpToggle<cr>";
              options.desc = "Toggle Marp preview";
            }
          ];
          userCommands = {
            MarpPreview = {
              command.__raw = terminalCommand "terminal:show()" ''
                local file = vim.api.nvim_buf_get_name(0)
                local root = file ~= "" and vim.fs.dirname(file) or vim.uv.cwd()
                Snacks.terminal.open({ ${builtins.toJSON (lib.getExe preview)}, root }, {
                    cwd = root,
                    start_insert = false,
                    auto_insert = false,
                    auto_close = false,
                    win = {
                        position = "bottom",
                        height = 10,
                        on_buf = function(terminal)
                            vim.api.nvim_buf_attach(terminal.buf, false, {
                                on_lines = function(_, buf, _, first, _, last)
                                    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
                                        local url = line:match("(https?://localhost:%d+/?)")
                                        if url then
                                            vim.schedule(function()
                                                local _, err = vim.ui.open(url)
                                                if err then
                                                    vim.notify(err, vim.log.levels.ERROR)
                                                end
                                            end)
                                            return true
                                        end
                                    end
                                end,
                            })
                        end,
                    },
                })
              '';
              desc = "Start Marp preview server";
            };
            MarpStop = {
              command.__raw = terminalCommand "terminal:close()" ''
                vim.notify("Marp preview is not running", vim.log.levels.INFO)
              '';
              desc = "Stop Marp preview server";
            };
            MarpToggle = {
              command.__raw = terminalCommand "terminal:close()" ''
                vim.cmd("MarpPreview")
              '';
              desc = "Toggle Marp preview server";
            };
            MarpStatus = {
              command.__raw =
                terminalCommand
                  ''
                    vim.notify("Marp preview running: " .. terminal.opts.cwd, vim.log.levels.INFO)
                  ''
                  ''
                    vim.notify("Marp preview is not running", vim.log.levels.INFO)
                  '';
              desc = "Show Marp preview server status";
            };
          };
        };
      };
    })
  ];
}
