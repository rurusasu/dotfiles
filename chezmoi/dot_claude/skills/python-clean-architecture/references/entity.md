# Entity 設計パターン

## ベストプラクティス

Entity は **ID で識別** され、**ビジネスロジック** を持つドメインオブジェクト。
Pydantic dataclass + Field で型安全なバリデーションを実現する。

```python
"""User エンティティ."""

from datetime import UTC, datetime
from uuid import UUID

from pydantic import Field
from pydantic.dataclasses import dataclass

from src.domain.entities.base import BaseEntity

# ビジネスルール定数はモジュールレベルで定義
MIN_NICKNAME_LENGTH = 2
MAX_NICKNAME_LENGTH = 50


@dataclass
class PersonalitySummary:
    """パーソナリティサマリーのドメインエンティティ."""

    summary: str = Field(description="サマリー")
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        description="更新日時",
    )
    is_active: bool = Field(default=True, description="アクティブフラグ")


@dataclass
class User(BaseEntity):
    """ユーザーエンティティ.

    ID で識別され、ビジネスロジックを内包する。
    """

    user_id: UUID = Field(description="ユーザーID")
    nickname: str = Field(
        description="ニックネーム",
        min_length=MIN_NICKNAME_LENGTH,
        max_length=MAX_NICKNAME_LENGTH,
    )
    personality: PersonalitySummary | None = Field(
        default=None, description="パーソナリティ"
    )
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        description="作成日時",
    )

    # --- ビジネスロジック ---

    def has_personality(self) -> bool:
        """パーソナリティが設定済みかを判定."""
        return self.personality is not None and self.personality.is_active

    @classmethod
    def create(
        cls,
        user_id: UUID,
        nickname: str,
        *,
        personality: PersonalitySummary | None = None,
    ) -> "User":
        """ファクトリメソッドで生成."""
        return cls(
            user_id=user_id,
            nickname=nickname,
            personality=personality,
        )
```

**ポイント**:

- `from pydantic.dataclasses import dataclass` を使用（標準 dataclass ではない）
- `Field()` で description とバリデーション制約を宣言
- ビジネスルール定数はモジュールレベルの大文字定数
- ファクトリメソッド (`create()`) で生成ロジックをカプセル化
- `__post_init__()` で複合バリデーションも可能

---

## NG パターン

### 1. 標準 dataclass を使う

```python
# ❌ Pydantic のバリデーションが効かない
from dataclasses import dataclass

@dataclass
class User:
    nickname: str  # min_length / max_length が検証されない
```

**理由**: `pydantic.dataclasses.dataclass` を使わないと `Field()` の制約が無視される。

---

### 2. Entity にインフラ層の依存を持ち込む

```python
# ❌ Entity が SQLAlchemy に依存
from sqlalchemy.orm import Session

@dataclass
class User:
    def save(self, session: Session) -> None:
        session.add(self)
        session.commit()
```

**理由**: Entity はドメイン層に属し、インフラ層（DB, ORM）に依存してはならない。永続化は Repository の責務。

---

### 3. Entity を単なるデータ入れ物にする

```python
# ❌ ビジネスロジックがない → ドメインモデル貧血症
@dataclass
class User:
    user_id: UUID
    nickname: str
    personality_summary: str | None = None
```

**理由**: Entity はビジネスルールを内包すべき。判定メソッドやファクトリメソッドでロジックを集約する。

---

### 4. Field の description を省略する

```python
# ❌ フィールドの意味が不明瞭
@dataclass
class User:
    user_id: UUID
    nickname: str
    pa: str | None = None  # 何の略？
```

**理由**: `Field(description=...)` は自己文書化の役割を果たす。スキーマ出力やドキュメント生成にも活用される。

---

### 5. バリデーション定数をマジックナンバーにする

```python
# ❌ 50 が何を意味するか不明
@dataclass
class User:
    nickname: str = Field(max_length=50)
    summary: str = Field(max_length=100)  # DB制約？UI制約？
```

**理由**: 定数にはビジネス上の意味を名前で付ける。`MAX_NICKNAME_LENGTH = 50` のようにモジュールレベルで定義する。

---

### 6. 可変コレクションをデフォルト値にする

```python
# ❌ ミュータブルデフォルト問題 → 全インスタンスで共有される
@dataclass
class ChatRoom:
    messages: list[str] = []
```

**理由**: ミュータブルなデフォルト値はインスタンス間で共有される。`Field(default_factory=list)` を使う。
