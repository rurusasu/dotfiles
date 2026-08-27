---
name: python-clean-architecture
description: |
  Python クリーンアーキテクチャのベストプラクティススキル。
  Entity, Value Object, DTO, Request/Response の設計パターンを提供。
  「Entity を作成して」「VO を作成して」「DTO を作成して」「リクエストモデルを作成して」などで使用。
---

# Python Clean Architecture スキル

Pydantic ベースの Entity / Value Object / DTO / Request-Response 設計パターン。

## レイヤー構成と型の使い分け

```
外部 (JSON)                 Application 層              Domain 層
─────────────              ──────────────              ──────────
TypedDict                   BaseModel (DTO)             dataclass (Entity/VO)
(生データ形式)        →     (バリデーション)       →    (ビジネスロジック)
                     model_validate()
```

| 型                     | 用途                                    | 基底クラス                                                        | 可変性                        |
| ---------------------- | --------------------------------------- | ----------------------------------------------------------------- | ----------------------------- |
| **Entity**             | ID で識別、ビジネスロジック保持         | `pydantic.dataclasses.dataclass`                                  | ミュータブル or `frozen=True` |
| **Value Object**       | 属性の等価性、副作用なし                | `pydantic.dataclasses.dataclass(frozen=True)` + `BaseValueObject` | イミュータブル                |
| **DTO (Input/Output)** | 層間データ転送、バリデーション          | `pydantic.BaseModel` (`frozen=True`)                              | イミュータブル                |
| **TypedDict**          | 生 JSON の型定義 (フレームワーク非依存) | `typing.TypedDict`                                                | N/A                           |

## 基本原則

1. **TypedDict → BaseModel の 2 層バリデーション**: 生 JSON は TypedDict で型定義し、`model_validate()` で DTO に変換
2. **Entity/VO は Pydantic dataclass**: `from pydantic.dataclasses import dataclass` を使用
3. **VO は常に `frozen=True`**: 値オブジェクトは不変
4. **DTO は `ConfigDict` で厳格設定**: `extra="forbid"`, `frozen=True`, `str_strip_whitespace=True`
5. **ビジネスロジックは Entity/VO に**: DTO はデータ転送のみ

## 参照ファイル

| ファイル                     | 内容                                                            |
| ---------------------------- | --------------------------------------------------------------- |
| `references/entity.md`       | Entity の設計パターンとアンチパターン                           |
| `references/value-object.md` | Value Object の設計パターンとアンチパターン                     |
| `references/dto.md`          | DTO + TypedDict + model_validate の設計パターンとアンチパターン |

## ワークフロー

1. 作成対象（Entity / VO / DTO）を判定
2. 対応する `references/` ファイルのベストプラクティスを参照
3. 既存コードの基底クラス・パターンに従って実装
4. アンチパターンに該当していないか確認
