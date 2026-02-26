#!/usr/bin/env python3
"""Python docstring を検証するスクリプト.

pydocstyle による標準チェックに加え、
拡張セクション(設計方針、参照など)の存在をチェックする。

使用例:
    python validate_docstring.py target.py
    python validate_docstring.py src/ --recursive
    python validate_docstring.py target.py --strict

参照:
    - pydocstyle: https://www.pydocstyle.org/
"""

import argparse
import ast
from pathlib import Path
import subprocess  # noqa: S404
import sys

# 拡張セクションのキーワード(英語のみ)
EXTENDED_SECTIONS = (
    "Design Decisions",
    "Change Rationale",
    "References",
    "Background",
    "Constraints",
)
# strict モードで必須とするセクション
REQUIRED_IN_STRICT = ("Design Decisions", "References")


def run_pydocstyle(target: Path, convention: str = "google") -> tuple[int, str]:
    """Pydocstyle を実行する.

    Args:
        target: 検証対象のファイルまたはディレクトリ。
        convention: 使用する規約。デフォルトは google。

    Returns:
        終了コードと出力のタプル。
    """
    cmd: list[str] = ["pydocstyle", "--convention", convention, str(target)]
    result = subprocess.run(
        cmd, check=False, shell=False, capture_output=True, text=True
    )
    return result.returncode, result.stdout + result.stderr


def extract_docstrings(filepath: Path) -> list[dict]:
    """ファイルから docstring を抽出する.

    Args:
        filepath: 対象ファイルパス。

    Returns:
        docstring 情報のリスト。各要素は name, lineno, docstring を持つ。
    """
    source = filepath.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(filepath))

    docstrings = []

    # モジュール docstring
    if ast.get_docstring(tree):
        docstrings.append(
            {
                "name": "<module>",
                "lineno": 1,
                "docstring": ast.get_docstring(tree),
            }
        )

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            docstring = ast.get_docstring(node)
            if docstring:
                docstrings.append(
                    {
                        "name": node.name,
                        "lineno": node.lineno,
                        "docstring": docstring,
                    }
                )

    return docstrings


def check_extended_sections(docstring: str, strict: bool = False) -> list[str]:
    """拡張セクションの存在をチェックする.

    Args:
        docstring: チェック対象の docstring。
        strict: True の場合、Design Decisions または References が必須。

    Returns:
        警告メッセージのリスト。
    """
    warnings = []

    found_sections = [
        section for section in EXTENDED_SECTIONS if f"{section}:" in docstring
    ]

    if strict and not any(req in found_sections for req in REQUIRED_IN_STRICT):
        warnings.append(
            "E901: Design Decisions or References section is required (--strict mode)"
        )

    return warnings


def validate_file(filepath: Path, strict: bool = False) -> list[str]:
    """単一ファイルを検証する.

    Args:
        filepath: 検証対象ファイル。
        strict: 厳格モード。

    Returns:
        問題のリスト。
    """
    issues = []

    # pydocstyle チェック
    returncode, output = run_pydocstyle(filepath)
    if returncode != 0 and output.strip():
        issues.extend((f"=== pydocstyle ({filepath}) ===", output.strip()))

    # 拡張セクションチェック
    try:
        docstrings = extract_docstrings(filepath)
        for item in docstrings:
            warnings = check_extended_sections(item["docstring"], strict)
            issues.extend(
                f"{filepath}:{item['lineno']} ({item['name']}): {warning}"
                for warning in warnings
            )
    except SyntaxError as e:
        issues.append(f"{filepath}: SyntaxError - {e}")

    return issues


def main() -> None:
    """メインエントリポイント."""
    parser = argparse.ArgumentParser(
        description="Python docstring を検証する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "target", type=Path, help="検証対象のファイルまたはディレクトリ"
    )
    parser.add_argument(
        "--recursive", "-r", action="store_true", help="ディレクトリを再帰的に検証"
    )
    parser.add_argument(
        "--strict",
        "-s",
        action="store_true",
        help="厳格モード(設計方針/参照を必須化)",
    )

    args = parser.parse_args()

    if not args.target.exists():
        print(f"Error: {args.target} が見つかりません", file=sys.stderr)
        sys.exit(1)

    # 対象ファイルを収集
    if args.target.is_file():
        files = [args.target]
    elif args.recursive:
        files = list(args.target.rglob("*.py"))
    else:
        files = list(args.target.glob("*.py"))

    if not files:
        print("検証対象のファイルがありません", file=sys.stderr)
        sys.exit(1)

    # 検証実行
    all_issues = []
    for filepath in files:
        issues = validate_file(filepath, args.strict)
        all_issues.extend(issues)

    # 結果出力
    if all_issues:
        print("\n".join(all_issues))
        print(f"\n{len(all_issues)} 件の問題が見つかりました")
        sys.exit(1)
    else:
        print(f"✅ {len(files)} ファイルを検証しました。問題ありません。")
        sys.exit(0)


if __name__ == "__main__":
    main()
