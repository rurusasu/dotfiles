# UI Operations (claude.ai/code)

## Create New Environment

1. Environment selector (bottom-right) → "環境を追加"
2. Fill: Name, Network Access (`Trusted`), Env Vars, Setup Script
3. "環境を作成"

## Edit Environment

1. Environment selector → hover over name → click ⚙ gear icon
2. Modify → "変更を保存"

## New Session

1. "新規セッション" (top-left)
2. Select repository (bottom-left)
3. Select environment (bottom-right)
4. Enter prompt → "送信"

## Debug Verification Task

Use this prompt to verify environment setup:

```
環境確認のみ: pwd, ls setup.sh, cd dashboard && npm test。コード変更不要。
```
