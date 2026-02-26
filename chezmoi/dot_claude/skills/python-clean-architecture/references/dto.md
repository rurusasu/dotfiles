# DTO + TypedDict + model_validate 設計パターン

## ベストプラクティス

フレームワーク非依存 (FastAPI / Django を使わない) の場合、生 JSON の受け渡しに **TypedDict** で型定義し、
**Pydantic BaseModel** の `model_validate()` でバリデーション済み DTO に変換する 2 層パターンを使う。

```python
"""Chat タスク用のリクエスト・レスポンススキーマ定義.

- TypedDict: バリデーション前の生データ (MessengerDict, ChatRequestDict)
- BaseModel: バリデーション済みモデル (MessengerModel, ChatRequestModel)
"""

from typing import ClassVar, NotRequired, Required, Self, TypedDict
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationInfo, model_validator
from pydantic.types import UUID7

from src.constant.ai_agent import AiAgentCode


# --- TypedDict: 生 JSON の型定義 (バリデーションなし) ---

class MessengerDict(TypedDict):
    """Messenger 情報の生データ形式."""

    messenger_id: Required[str]
    user_id: Required[str]
    ai_agent_code: Required[str]


class ChatRequestDict(TypedDict):
    """Chat リクエストの生データ形式."""

    chat_room_id: Required[str]
    messenger: Required[MessengerDict]
    is_counseling_start: NotRequired[bool]


# --- BaseModel DTO: バリデーション + 型変換 ---

class MessengerModel(BaseModel):
    """Messenger 情報のバリデーション済みモデル."""

    model_config: ClassVar[ConfigDict] = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
        frozen=True,
        validate_assignment=True,
        revalidate_instances="always",
    )

    messenger_id: UUID7 = Field(..., description="メッセンジャーID")
    user_id: UUID7 = Field(..., description="ユーザーID")
    ai_agent_code: AiAgentCode = Field(..., description="AIエージェントコード")


class ChatRequestModel(BaseModel):
    """Chat リクエストのバリデーション済みモデル.

    model_validate に context={"expected_ai_agent_code": ...} を渡すと
    messenger.ai_agent_code との整合性を検証する。
    """

    model_config: ClassVar[ConfigDict] = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
        frozen=True,
        validate_assignment=True,
        revalidate_instances="always",
    )

    chat_room_id: UUID7 = Field(..., description="チャットルームID")
    messenger: MessengerModel = Field(..., description="メッセンジャー情報")
    is_counseling_start: bool | None = Field(
        default=None, description="カウンセリング開始かどうか"
    )

    @model_validator(mode="after")
    def _check_expected_ai_agent_code(self, info: ValidationInfo) -> Self:
        """context に expected_ai_agent_code がある場合、整合性を検証."""
        if not isinstance(info.context, dict):
            return self
        expected = info.context.get("expected_ai_agent_code")
        if expected is None:
            return self
        if self.messenger.ai_agent_code != expected:
            msg = (
                f"Invalid ai_agent_code: expected {expected}, "
                f"got {self.messenger.ai_agent_code}"
            )
            raise ValueError(msg)
        return self


# --- 出力 DTO ---

class ChatResponseModel(BaseModel):
    """Chat UseCase の実行結果モデル.

    model_dump(mode="json") で UUID → str 自動変換。
    """

    model_config: ClassVar[ConfigDict] = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
        frozen=True,
        validate_assignment=True,
        revalidate_instances="always",
    )

    success: bool = Field(..., description="実行成功かどうか")
    chat_room_id: UUID = Field(..., description="チャットルームID")
    message: str | None = Field(default=None, description="生成メッセージ")
    error_message: str | None = Field(default=None, description="エラーメッセージ")


# --- 使用例 ---
# validated = ChatRequestModel.model_validate(
#     raw_data,
#     context={"expected_ai_agent_code": AiAgentCode.AI_COUNSELOR},
# )
# response = ChatResponseModel(success=True, chat_room_id=..., message=...)
# payload = response.model_dump(mode="json", exclude_none=True)
```

**ポイント**:

- **TypedDict**: 生 JSON の構造を明示。`Required[]` / `NotRequired[]` で必須・任意を表現
- **BaseModel DTO**: `model_validate()` で TypedDict → DTO 変換 + バリデーション同時実行
- **ConfigDict 標準設定**: `extra="forbid"`, `frozen=True`, `str_strip_whitespace=True`
- **context パターン**: `model_validate(data, context={...})` でタスク固有のバリデーションを注入
- **出力シリアライズ**: `model_dump(mode="json")` で UUID → str 自動変換

---

## NG パターン

### 1. TypedDict を使わず生 dict で型を省略する

```python
# ❌ 型情報がなく、キー名の typo に気づけない
def process_request(data: dict) -> None:
    chat_room_id = data["chat_room_id"]
    messenger_id = data["messenger_id"]   # typo に気づけない
```

**理由**: TypedDict は IDE の補完・型チェックを有効化し、JSON 構造の契約を明示する。

---

### 2. TypedDict に直接バリデーションを実装する

```python
# ❌ TypedDict はバリデーション機能を持たない
class MessengerDict(TypedDict):
    messenger_id: str  # UUID かどうか検証できない

# 呼び出し側で手動検証 → 散在する
if not is_valid_uuid(data["messenger_id"]):
    raise ValueError("Invalid UUID")
```

**理由**: TypedDict は「生データの型定義」のみ。バリデーションは BaseModel の `model_validate()` で一元化する。

---

### 3. ConfigDict の `extra="forbid"` を省略する

```python
# ❌ 予期しないフィールドが静かに無視される
class MessengerModel(BaseModel):
    messenger_id: UUID7
    user_id: UUID7

data = {"messenger_id": "...", "user_id": "...", "typo_field": "oops"}
MessengerModel.model_validate(data)  # typo_field が黙って無視される
```

**理由**: `extra="forbid"` がないと、フィールド名の typo や不要データの混入を検出できない。

---

### 4. `frozen=True` を省略する

```python
# ❌ 外部から変更可能 → 意図しない状態変化
class ChatRequestModel(BaseModel):
    chat_room_id: UUID7

req = ChatRequestModel.model_validate(data)
req.chat_room_id = UUID("...")  # 変更できてしまう
```

**理由**: DTO は層間を移動するデータ。途中で変更されると原因追跡が困難になる。`frozen=True` で不変性を保証する。

---

### 5. model_validate を使わず手動コンストラクタで変換する

```python
# ❌ 手動変換 → バリデーションが漏れやすい
def to_model(data: ChatRequestDict) -> ChatRequestModel:
    return ChatRequestModel(
        chat_room_id=UUID(data["chat_room_id"]),
        messenger=MessengerModel(
            messenger_id=UUID(data["messenger"]["messenger_id"]),
            user_id=UUID(data["messenger"]["user_id"]),
            ai_agent_code=AiAgentCode(data["messenger"]["ai_agent_code"]),
        ),
    )
```

**理由**: `model_validate()` はネストされた dict も再帰的にバリデーションする。手動変換ではバリデーションの漏れや重複が発生する。

---

### 6. 出力を手動 dict で構築する

```python
# ❌ キー名 typo、型不整合のリスク
result = {
    "success": True,          # typo!
    "chat_room_id": str(id), # 手動変換
    "message": response,
}
```

**理由**: `model_dump(mode="json")` は UUID → str 等の変換を自動実行し、スキーマに沿った正しい出力を保証する。

---

### 7. context パターンを使わず条件分岐で検証する

```python
# ❌ タスクごとの検証が呼び出し側に散在
validated = ChatRequestModel.model_validate(data)
if task_type == "counselor":
    if validated.messenger.ai_agent_code != AiAgentCode.AI_COUNSELOR:
        raise ValueError("Wrong agent code")
elif task_type == "simulator":
    if validated.messenger.ai_agent_code != AiAgentCode.CHAT_SIMULATOR:
        raise ValueError("Wrong agent code")
```

**理由**: `context` パターンにより、バリデーションロジックをモデル内に集約し、呼び出し側をシンプルに保てる。

---

### 8. TypedDict と BaseModel で異なるフィールド名を使う

```python
# ❌ フィールド名が不一致 → model_validate で変換不能
class MessengerDict(TypedDict):
    msgr_id: Required[str]     # 省略名

class MessengerModel(BaseModel):
    messenger_id: UUID7        # 正式名 → KeyError
```

**理由**: TypedDict と BaseModel のフィールド名は一致させる。不一致があると `model_validate()` で変換に失敗する。必要なら `alias` を使う。
