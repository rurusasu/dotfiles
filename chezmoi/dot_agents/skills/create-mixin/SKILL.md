---
name: create-mixin
description: UseCaseで共通化できるメソッドをMixinパターンで抽出するスキル。「Mixinを作成して」「共通メソッドを抽出して」「UseCaseを共通化して」などのリクエストで使用。
---

# UseCase Mixin作成スキル

UseCaseで重複しているメソッドをMixinパターンで共通化するスキル。

## 基本原則

### 1. 命名規則

- **Lazy importを使う場合**: クラス名に `Lazy` を含める
  - 例: `LazyPromptLoaderMixin`, `LazyChatContextLoaderMixin`
- **Lazy importを使わない場合**: `Lazy` を含めない
  - 例: `RepositoryCacheMixin`

### 2. 継承階層

```python
RepositoryCacheMixin              # 基底（リポジトリキャッシュ）
├── LazyPromptLoaderMixin         # プロンプト取得
└── LazyChatContextLoaderMixin    # Chat関連エンティティ取得
```

### 3. 必須属性

Mixinを使用するクラスは以下の属性を持つこと：

```python
_repository_cache: dict[int, dict[str, Any]] = {}
```

## Mixin作成手順

1. **重複検出**: 複数のUseCaseで同一実装のメソッドを探す
2. **抽出候補選定**: 3つ以上のファイルで重複 → 高優先度
3. **Lazy判定**: メソッド内でimportしているか確認
4. **命名**: Lazyなら `Lazy*Mixin`、そうでなければ `*Mixin`
5. **継承設計**: 依存関係を考慮して階層を決定
6. **型定義**: Protocol, TypeVar を適切に定義

## ファイル配置

```
src/usecase/
├── mixin.py          # 全Mixinクラスを配置
├── affinity_recommend.py
├── ai_counselor.py
└── ...
```

## 使用例

```python
# mixin.py
class RepositoryCacheMixin:
    _repository_cache: dict[int, dict[str, Any]]

    def _get_repository(self, session, name, cls): ...
    def _clear_repository_cache(self, session): ...

class LazyPromptLoaderMixin(RepositoryCacheMixin):
    def _lazy_get_prompt_template(self, prompt_name, session): ...

# affinity_recommend.py
from src.usecase.mixin import LazyPromptLoaderMixin

class AffinityRecommenderUseCase(LazyPromptLoaderMixin):
    def __init__(self, ...):
        self._repository_cache: dict[int, dict[str, Any]] = {}
```

## 現在定義されているMixin

### RepositoryCacheMixin

- `_get_repository(session, repository_name, repository_class)`: セッションごとにリポジトリをキャッシュして取得
- `_clear_repository_cache(session)`: 指定セッションのリポジトリキャッシュをクリア

### LazyPromptLoaderMixin (RepositoryCacheMixin継承)

- `_lazy_get_prompt_template(agent_prompt_name, session)`: プロンプトテンプレートを取得

### LazyChatContextLoaderMixin (RepositoryCacheMixin継承)

- `_lazy_get_chat_room(chat_room_id, messenger_id, session, include_soft_deleted_room)`: チャットルームを取得
- `_lazy_get_message_history(chat_room_id, get_message_limit, session)`: メッセージ履歴を取得
- `_lazy_get_user(user_id, session)`: ユーザーを取得
- `_lazy_get_user_with_options(user_id, session, dummy_user_include_chat_room_id, include_deleted)`: オプション付きでユーザーを取得
- `_lazy_create_text_message(chat_room_id, messenger_id, content, session)`: テキストメッセージを作成
- `_lazy_complete_chat_session(chat_room_id, messenger_id, user_id, session)`: チャットセッションを完了

## 避けるべきパターン

- UseCase固有のロジックをMixinに入れる
- 過度な抽象化（1-2ファイルでしか使わないメソッド）
- 循環依存を生むimport構造
