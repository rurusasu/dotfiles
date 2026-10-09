{ config, lib, ... }:
{
  # システムのタイムゾーンを日本時間にする。
  time.timeZone = "Asia/Tokyo";

  system.activationScripts.postActivation.text = lib.mkAfter ''
    # macOS の設定変更をログアウトなしで即時反映する。
    /usr/bin/sudo -u ${lib.escapeShellArg config.system.primaryUser} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  system.defaults = {
    dock = {
      # Dock のアイコンサイズを 50 ピクセルにする。
      tilesize = 50;
      # ポインタを画面端に移動したときだけ Dock を表示する。
      autohide = true;
      # アプリ起動時のアニメーションを有効にする。
      launchanim = true;
      # 起動中のアプリにインジケーターを表示する。
      show-process-indicators = true;
      # 最近使ったアプリを Dock に表示しない。
      show-recents = false;
      # 4 本指で広げてデスクトップを表示する。
      showDesktopGestureEnabled = true;
      # 4 本指で上下にスワイプして Mission Control を表示する。
      showMissionControlGestureEnabled = true;
      # App Exposé ジェスチャーを無効にする。
      showAppExposeGestureEnabled = false;
      # Launchpad ジェスチャーを無効にする。
      showLaunchpadGestureEnabled = false;
      # 最近使った順に操作スペースを並べ替えない。
      mru-spaces = false;
    };

    trackpad = {
      # トラックパッドをタップしてクリックできるようにする。
      Clicking = true;
      # 2本指クリックを副ボタン（右クリック）として使う。
      TrackpadRightClick = true;
    };

    finder = {
      # 新しいウインドウは「最近の項目」ではなくホームフォルダーを開く。
      NewWindowTarget = "Home";
      # Finder のタイトルバーに現在のパスを表示する。
      _FXShowPosixPathInTitle = true;
      # ファイル名の拡張子を表示する。
      AppleShowAllExtensions = true;
      # 拡張子を変更するときに確認を表示する。
      FXEnableExtensionChangeWarning = true;
      # Finder のメニューから終了できるようにする。
      QuitMenuItem = true;
      # Finder ウインドウにパスバーを表示する。
      ShowPathbar = true;
      # Finder ウインドウにステータスバーを表示する。
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      # アプリ全体でファイルの拡張子を常に表示する。
      AppleShowAllExtensions = true;
      # 2本指で上にスワイプするとページの下へ進む（ナチュラルスクロール）。
      "com.apple.swipescrolldirection" = true;
      # ダークモードを有効にする。
      AppleInterfaceStyle = "Dark";
      # 入力時の自動大文字化、自動置換、スペル修正を無効にする。
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    loginwindow = {
      # ゲストユーザーでのログインを無効にする。
      GuestEnabled = false;
      # ログイン画面にユーザー一覧を表示する。
      SHOWFULLNAME = false;
    };

    # Omarchy のキー設定と競合する macOS 標準ショートカットを無効にする。
    CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      "60" = {
        enabled = false;
        value = {
          parameters = [
            32
            49
            1048576
          ];
          type = "standard";
        };
      };
      "61" = {
        enabled = false;
        value = {
          parameters = [
            32
            49
            1572864
          ];
          type = "standard";
        };
      };
      "64" = {
        enabled = false;
        value = {
          parameters = [
            65535
            49
            1048576
          ];
          type = "standard";
        };
      };
      "65" = {
        enabled = false;
        value = {
          parameters = [
            65535
            49
            1572864
          ];
          type = "standard";
        };
      };
      "156" = {
        enabled = false;
        value = {
          parameters = [
            65535
            49
            393216
          ];
          type = "standard";
        };
      };
    };
  };
}
