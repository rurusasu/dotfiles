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
  assets = [
    (asset feed.app.platforms.linux-x86_64)
  ]
  ++ map asset (builtins.filter (entry: entry.platform == "linux-x86_64") feed.control.packages);
}
