feed:
let
  tag = "v${feed.app.version}";
  base = "https://github.com/Niko1221/Strata/releases/download/${tag}";
  asset = entry: {
    name = builtins.baseNameOf entry.url;
    # Even a versioned upstream feed links Desktop through /latest/download/.
    # Resolve every asset under this release so a later release cannot replace it.
    browser_download_url = "${base}/${builtins.baseNameOf entry.url}";
    digest = "sha256:${entry.sha256}";
  };
in
{
  tag_name = tag;
  assets =
    map asset (
      builtins.filter (entry: entry != null) [
        (feed.app.platforms.linux-x86_64 or null)
        (feed.app.platforms.darwin-aarch64 or null)
      ]
    )
    ++ map asset (
      builtins.filter (
        entry:
        builtins.elem entry.platform [
          "linux-x86_64"
          "macos-arm64"
        ]
      ) feed.control.packages
    );
}
