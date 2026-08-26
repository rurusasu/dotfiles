# Docstring Examples

## Module docstring

ファイル冒頭に記述。モジュールの目的、主要コンポーネント、使用例を含める。

```python
"""データベース接続とセッション管理を提供するモジュール.

SQLAlchemy 2.0 と AlloyDB Connector を使用し、
コンテキストマネージャーベースのライフサイクル管理を実現する。

Main Components:
    - DatabaseManager: 接続プールとセッションを管理
    - ConnectionConfig: 接続設定のデータクラス
    - HealthCheckResult: ヘルスチェック結果

Design Decisions:
    本モジュールはリソースリーク防止を最優先とし、
    すべての接続操作をコンテキストマネージャーで囲む設計を採用。
    明示的な close() 呼び出しは非推奨。

Example:
    from db import DatabaseManager, ConnectionConfig

    config = ConnectionConfig(host="localhost", database="mydb")
    manager = DatabaseManager(config)

    with manager.connect():
        with manager.session.begin() as session:
            result = session.execute(query)

References:
    - SQLAlchemy 2.0 Session: https://docs.sqlalchemy.org/en/20/orm/session.html
    - AlloyDB Connector: https://cloud.google.com/alloydb/docs/connect-language-connectors
"""
```

## Class docstring

```python
class DatabaseManager:
    """コンテキストマネージャーでライフサイクルを管理するデータベース接続マネージャー.

    SQLAlchemy 2.0 のベストプラクティスに従い、sessionmaker.begin() を使用して
    自動トランザクション管理を行う。

    Design Decisions:
        1. **AlloyDB Connector のライフサイクル管理**:
           本番環境では、AlloyDB Connector は SQLAlchemy Engine より長く生存する必要がある。
           Engine は `creator=lambda: connector.connect(...)` を使用して Connector インスタンスを
           参照するため、Connector が Engine より先に dispose されると接続作成が失敗する。

           正しいライフサイクル順序::

               with AlloyDBConnector() as connector:     # 1. Connector 作成
                   engine = create_engine(creator=...)   # 2. Engine 作成
                   ...engine を使用...
                   engine.dispose()                      # 3. Engine を先に dispose
               # 4. Connector が dispose（with ブロック終了時）

        2. **コンテキストマネージャーパターン**:
           `connect()` メソッドは適切なリソースクリーンアップ順序を保証する
           コンテキストマネージャーを返す。

        3. **ヘルスチェックの到達性**:
           ヘルスチェックは `connect()` の前に呼び出される可能性がある
           （例: コンテナ起動時の Kubernetes readiness プローブ）。
           この場合、`_check_connection()` は最小限のプール設定で一時的な
           Connector + Engine を作成し、接続を検証後、正しい順序で dispose する。

    Attributes:
        config (ConnectionConfig): 接続設定。
        session (sessionmaker): セッションファクトリ。connect() 後に有効。

    Example:
        db_manager = DatabaseManager(config)

        # 通常の操作 - connect() コンテキストマネージャーを使用
        with db_manager.connect():
            with db_manager.session.begin() as session:
                session.execute(...)
                # 成功時は自動コミット、例外時は自動ロールバック

        # Connector と Engine は正しい順序で自動的にクリーンアップ

        # ヘルスチェックは connect() コンテキストの内外で動作
        health = db_manager.health_check()  # いつでも動作

    References:
        - SQLAlchemy 2.0: https://docs.sqlalchemy.org/en/20/orm/session_basics.html
        - AlloyDB Connector: https://github.com/GoogleCloudPlatform/alloydb-python-connector
    """
```

## Method docstring

```python
def connect(self) -> Generator[None, None, None]:
    """データベース接続を確立し、コンテキストマネージャーを返す.

    Connector と Engine を初期化し、コンテキスト終了時に
    正しい順序（Engine → Connector）でクリーンアップする。

    Yields:
        None: コンテキスト内で self.session が使用可能になる。

    Raises:
        ConnectionError: 接続確立に失敗した場合。
        TimeoutError: 接続タイムアウトの場合。

    Example:
        >>> with db_manager.connect():
        ...     with db_manager.session.begin() as session:
        ...         session.execute(text("SELECT 1"))

    Note:
        このメソッドは再入可能ではない。
        ネストした呼び出しは想定外の動作を引き起こす可能性がある。
    """
```

## Function docstring (simple example)

```python
def calculate_retry_delay(
    attempt: int,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
) -> float:
    """指数バックオフでリトライ遅延を計算する.

    Args:
        attempt: 現在の試行回数（0始まり）。
        base_delay: 基本遅延秒数。
        max_delay: 最大遅延秒数。

    Returns:
        次のリトライまでの遅延秒数。

    Example:
        >>> calculate_retry_delay(0)
        1.0
        >>> calculate_retry_delay(3)
        8.0
        >>> calculate_retry_delay(10)  # max_delay でキャップ
        60.0

    Design Decisions:
        ジッターは追加していない。呼び出し側で必要に応じて追加する想定。
        AWS の推奨（Full Jitter）は別関数 `calculate_retry_delay_with_jitter` で提供。

    References:
        - AWS Exponential Backoff: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
    """
```

## Property docstring

```python
@property
def is_connected(self) -> bool:
    """接続状態を返す.

    Returns:
        接続が確立されている場合は True。

    Note:
        このプロパティは接続の有効性を保証しない。
        実際のクエリ実行時に接続が切れている可能性がある。
    """
```

## Exception class docstring

```python
class DatabaseConnectionError(Exception):
    """データベース接続エラーを表す例外.

    Attributes:
        host (str): 接続先ホスト。
        port (int): 接続先ポート。
        original_error (Exception): 元の例外。

    Example:
        >>> raise DatabaseConnectionError("localhost", 5432, original)
    """
```

## Dataclass docstring

```python
@dataclass
class ConnectionConfig:
    """データベース接続設定.

    Attributes:
        host: データベースホスト。
        port: ポート番号。デフォルトは 5432。
        database: データベース名。
        user: 接続ユーザー。
        password: パスワード。環境変数から取得推奨。
        pool_size: コネクションプールサイズ。デフォルトは 5。

    Example:
        >>> config = ConnectionConfig(
        ...     host="localhost",
        ...     database="mydb",
        ...     user="admin",
        ...     password=os.environ["DB_PASSWORD"],
        ... )

    Note:
        password を直接コードに記述しないこと。
    """
```
