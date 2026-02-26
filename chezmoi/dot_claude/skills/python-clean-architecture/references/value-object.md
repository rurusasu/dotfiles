# Value Object 設計パターン

## ベストプラクティス

Value Object (VO) は **属性の等価性** で判定され、常に **イミュータブル** なドメインオブジェクト。
`frozen=True` + `BaseValueObject` 継承で不変性を保証する。

```python
"""Chat context value objects."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field
from pydantic.dataclasses import dataclass
from pydantic.types import UUID7

from src.constant.chat_room import MAX_TURNS, Role
from src.domain.value_objects.base import BaseValueObject


@dataclass(frozen=True)
class ParticipantSnapshot(BaseValueObject):
    """チャット参加者のイミュータブルスナップショット."""

    user_id: UUID7 = Field(description="ユーザーID")
    messenger_id: UUID7 = Field(description="メッセンジャーID")
    role: Role = Field(description="ロール")
    ai_agent_code: str | None = Field(
        default=None, description="AIエージェントコード"
    )

    def is_ai_agent(self) -> bool:
        """AI エージェントかどうかを判定."""
        return self.ai_agent_code is not None

    def is_user(self) -> bool:
        """実ユーザーかどうかを判定."""
        return self.role == Role.USER and self.ai_agent_code is None


@dataclass(frozen=True)
class ChatContext(BaseValueObject):
    """イミュータブルなチャットコンテキスト VO.

    ChatRoom エンティティを埋め込まず、集約間結合を回避する。
    """

    chat_room_id: UUID7 = Field(description="チャットルームID")
    sender_messenger_id: UUID7 = Field(description="送信者メッセンジャーID")
    participants: tuple[ParticipantSnapshot, ...] = Field(
        default_factory=tuple, description="参加者リスト"
    )
    messages: tuple[str, ...] = Field(
        default_factory=tuple, description="メッセージリスト"
    )
    turn_count: int = Field(default=0, description="ターン数", ge=0)
    max_turns: int = Field(default=MAX_TURNS, description="最大ターン数")

    # --- 副作用のないメソッド ---

    def is_max_turns_reached(self) -> bool:
        """最大ターンに到達したか判定."""
        return self.turn_count >= self.max_turns

    def get_sender(self) -> ParticipantSnapshot | None:
        """送信者の参加者スナップショットを取得."""
        return next(
            (p for p in self.participants
             if p.messenger_id == self.sender_messenger_id),
            None,
        )

    # --- イミュータブル更新 (新インスタンスを返す) ---

    def increment_turn(self) -> ChatContext:
        """ターン数を +1 した新しい ChatContext を返す."""
        return ChatContext(
            chat_room_id=self.chat_room_id,
            sender_messenger_id=self.sender_messenger_id,
            participants=self.participants,
            messages=self.messages,
            turn_count=self.turn_count + 1,
            max_turns=self.max_turns,
        )
```

**ポイント**:

- `@dataclass(frozen=True)` で代入を禁止し不変性を保証
- `BaseValueObject` 継承で等価性判定 (`__eq__`, `__hash__`) を統一
- コレクションは `tuple` を使用（`list` ではなく）
- 更新メソッドは **新しいインスタンスを返す** (`increment_*` パターン)

---

## NG パターン

### 1. `frozen=True` を付けない

```python
# ❌ 外部からフィールドを変更できてしまう
@dataclass
class ChatContext(BaseValueObject):
    turn_count: int = 0

ctx = ChatContext(turn_count=0)
ctx.turn_count = 5  # VO の不変性が壊れる
```

**理由**: VO は不変であることが前提。`frozen=True` がないと外部から状態変更され、予測不能な副作用が生じる。

---

### 2. コレクションに `list` を使う

```python
# ❌ list はミュータブル → frozen=True でも中身を変更できる
@dataclass(frozen=True)
class ChatContext(BaseValueObject):
    messages: list[str] = Field(default_factory=list)

ctx = ChatContext(messages=["hello"])
ctx.messages.append("world")  # frozen なのに変更できてしまう!
```

**理由**: `frozen=True` はフィールドの再代入を防ぐが、ミュータブルなオブジェクト内部の変更は防げない。`tuple` で真の不変性を実現する。

---

### 3. VO を直接変更するメソッドを作る

```python
# ❌ object.__setattr__ で frozen を回避 → 設計意図の破壊
@dataclass(frozen=True)
class ChatContext(BaseValueObject):
    turn_count: int = 0

    def increment_turn(self) -> None:
        object.__setattr__(self, "turn_count", self.turn_count + 1)
```

**理由**: `object.__setattr__` による回避は `frozen=True` の設計意図を破壊する。常に新しいインスタンスを返すこと。

---

### 4. BaseValueObject を継承しない

```python
# ❌ 等価性判定が統一されない
@dataclass(frozen=True)
class Money:
    amount: int
    currency: str
```

**理由**: `BaseValueObject` を継承しないと、等価性判定とハッシュ計算が統一されず、`dict` キーや `set` での比較で予期しない挙動になる。

---

### 5. Entity を VO 内に埋め込む

```python
# ❌ 集約間の結合が生まれる
@dataclass(frozen=True)
class ChatContext(BaseValueObject):
    chat_room: ChatRoom  # Entity を直接保持 → 集約境界を超える
```

**理由**: VO に Entity を埋め込むと集約境界を超える依存が生まれる。必要な情報は ID やスナップショット (VO) として切り出す。

---

### 6. VO に副作用のあるメソッドを持たせる

```python
# ❌ VO から外部サービスを呼ぶ
@dataclass(frozen=True)
class ModerationResult(BaseValueObject):
    status: str

    def notify(self, pubsub_service: IRedisPubSubService) -> None:
        pubsub_service.publish(self.status)  # 副作用!
```

**理由**: VO のメソッドは純粋関数（入力→出力のみ、副作用なし）であるべき。外部呼び出しは Domain Service や UseCase の責務。
