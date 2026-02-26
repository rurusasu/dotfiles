# Google Style Docstring Specification

## Basic Structure

```python
"""一行目: 簡潔な要約（命令形、ピリオドで終わる）.

詳細な説明。複数行にわたってもよい。
空行で一行目と区切る。

セクション:
    セクション内容
"""
```

## Standard Sections

### Args

引数を記述。型は括弧内に、説明はコロン後に。

```python
Args:
    path (str): ファイルパス。
    timeout (int, optional): タイムアウト秒数。デフォルトは 30。
    *args: 可変長引数。
    **kwargs: キーワード引数。
```

### Returns

戻り値を記述。複数の値を返す場合はタプルとして記述。

```python
Returns:
    bool: 処理が成功した場合は True。

Returns:
    tuple[str, int]: ファイル名とサイズのタプル。
```

### Yields

ジェネレータの場合に使用。

```python
Yields:
    str: 各行のテキスト。
```

### Raises

発生しうる例外を記述。

```python
Raises:
    FileNotFoundError: ファイルが存在しない場合。
    ValueError: 引数が不正な場合。
```

### Attributes

クラス属性を記述（クラス docstring 内で使用）。

```python
Attributes:
    name (str): インスタンス名。
    count (int): カウンター値。
```

### Example / Examples

使用例を記述。doctest 形式推奨。

```python
Example:
    >>> calc_sum(1, 2)
    3

Examples:
    基本的な使用方法::

        result = process_data(input_data)
        print(result)

    エラーハンドリング::

        try:
            process_data(None)
        except ValueError as e:
            print(f"Error: {e}")
```

### Note / Notes

補足情報を記述。

```python
Note:
    この関数はスレッドセーフではない。

Notes:
    - Python 3.10 以上が必要。
    - 大量データの場合はバッチ処理を推奨。
```

### Warning / Warnings

警告事項を記述。

```python
Warning:
    この操作は元に戻せない。
```

### See Also

関連する関数やクラスへの参照。

```python
See Also:
    other_function: 関連する別の関数。
    SomeClass: 関連するクラス。
```

### Todo

将来の改善点を記述。

```python
Todo:
    * 非同期版を実装する。
    * キャッシュ機構を追加する。
```

## Type Annotations

型アノテーションがある場合、docstring での型記述は省略可。

```python
def greet(name: str, times: int = 1) -> str:
    """挨拶メッセージを生成する.

    Args:
        name: 挨拶する相手の名前。
        times: 繰り返し回数。デフォルトは 1。

    Returns:
        挨拶メッセージ。
    """
```

## Indentation

- セクション名の後にコロン
- 内容は 4 スペースインデント
- 複数行の説明は揃える
