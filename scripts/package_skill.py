"""
Build one release zip that expands into the strict LuaSkill top-level directory.
构建一个发布 zip，并在解压后还原严格的 LuaSkill 顶层目录。
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

import yaml


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Load the skill manifest from disk.
从磁盘加载技能清单。
"""
def load_manifest(root: Path) -> dict:
    with (root / "skill.yaml").open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle) or {}
    if not isinstance(payload, dict):
        raise RuntimeError("skill.yaml must contain one YAML object")
    return payload


"""
Return the semantic package version declared by the manifest.
返回清单中声明的语义化包版本。
"""
def manifest_version(manifest: dict) -> str:
    version = manifest.get("version")
    if not isinstance(version, str) or not version.strip():
        raise RuntimeError("skill.yaml must contain a non-empty version")
    return version.strip()


"""
Resolve the effective package version and enforce it against CLI or GitHub tag inputs.
解析最终打包版本，并强制要求其与命令行或 GitHub 标签输入保持一致。
"""
def resolve_version(manifest: dict, cli_version: str | None) -> str:
    declared_version = manifest_version(manifest)

    if cli_version and cli_version.strip() != declared_version:
        raise RuntimeError(
            f"--version must match skill.yaml version {declared_version}, got {cli_version.strip()}"
        )

    import os

    ref_name = os.environ.get("GITHUB_REF_NAME", "").strip()
    if ref_name:
        expected_tag = f"v{declared_version}"
        if ref_name != expected_tag:
            raise RuntimeError(
                f"GITHUB_REF_NAME must match {expected_tag}, got {ref_name}"
            )

    return declared_version


"""
Return a normalized release asset base URL without a trailing slash.
返回去除尾部斜杠后的规范化发布资产基础 URL。
"""
def normalize_base_url(base_url: str | None, version: str) -> str:
    if base_url is None or not base_url.strip():
        return f"https://github.com/LuaSkills/vulcan-file/releases/download/v{version}"
    return base_url.strip().rstrip("/")


"""
Return the list of repository-relative paths included in the release package.
返回发布包中应包含的仓库相对路径列表。
"""
def collect_package_paths(root: Path) -> list[Path]:
    include_names = {
        "skill.yaml",
        "dependencies.yaml",
        "README.md",
        "README.zh-CN.md",
        "LICENSE",
        "runtime",
        "schemas",
        "help",
        "overflow_templates",
        "resources",
        "licenses",
    }

    collected: list[Path] = []
    for path in root.iterdir():
        if path.name not in include_names:
            continue
        if path.is_file():
            collected.append(path)
        else:
            collected.extend(sorted(item for item in path.rglob("*") if item.is_file()))
    return collected


"""
Build the release zip and checksum file under the selected output directory.
在选定输出目录下构建发布 zip 与校验文件。
"""
def build_package(root: Path, out_dir: Path, version: str) -> tuple[Path, Path]:
    manifest = load_manifest(root)
    skill_name = root.name
    display_name = manifest.get("name", skill_name)
    if not isinstance(display_name, str) or not display_name:
        raise RuntimeError("skill.yaml must contain a non-empty name")

    out_dir.mkdir(parents=True, exist_ok=True)
    package_name = f"{skill_name}-v{version}-skill.zip"
    checksum_name = f"{skill_name}-v{version}-checksums.txt"
    package_path = out_dir / package_name
    checksum_path = out_dir / checksum_name

    with ZipFile(package_path, "w", compression=ZIP_DEFLATED) as archive:
        for file_path in collect_package_paths(root):
            relative_path = file_path.relative_to(root)
            archive_path = Path(skill_name) / relative_path
            archive.write(file_path, archive_path.as_posix())

    digest = hashlib.sha256(package_path.read_bytes()).hexdigest()
    checksum_path.write_text(f"{digest}  {package_name}\n", encoding="utf-8")
    return package_path, checksum_path


"""
Build one source metadata YAML file for URL-based installation and update tests.
构建一个用于 URL 安装与更新测试的来源描述 YAML 文件。
"""
def build_source_metadata(
    root: Path,
    out_dir: Path,
    version: str,
    base_url: str | None,
    package_path: Path,
    checksum_path: Path,
) -> Path:
    manifest = load_manifest(root)
    skill_name = root.name
    display_name = manifest.get("name", skill_name)
    if not isinstance(display_name, str) or not display_name:
        raise RuntimeError("skill.yaml must contain a non-empty name")

    source_name = f"{skill_name}-v{version}-source.yaml"
    source_path = out_dir / source_name
    normalized_base_url = normalize_base_url(base_url, version)
    package_name = package_path.name
    checksum_name = checksum_path.name
    checksum_sha256 = checksum_path.read_text(encoding="utf-8").split()[0]

    payload = {
        "skill_id": skill_name,
        "name": display_name,
        "version": version,
        "source": {
            "kind": "url",
            "locator": f"{normalized_base_url}/{source_name}",
        },
        "package": {
            "url": f"{normalized_base_url}/{package_name}",
            "sha256": checksum_sha256,
            "filename": package_name,
        },
        "checksums": {
            "url": f"{normalized_base_url}/{checksum_name}",
            "filename": checksum_name,
        },
        "release": {
            "tag": f"v{version}",
        },
    }
    source_path.write_text(
        yaml.safe_dump(payload, sort_keys=False, allow_unicode=False),
        encoding="utf-8",
    )
    return source_path


"""
Parse command-line arguments for the package builder.
解析打包脚本使用的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package one LuaSkill release zip.")
    parser.add_argument("--out-dir", default="dist", help="Output directory for release assets.")
    parser.add_argument(
        "--base-url",
        default=None,
        help="Optional base URL used to build generated source metadata; defaults to the LuaSkills/vulcan-file GitHub release URL.",
    )
    parser.add_argument(
        "--emit-source-yaml",
        action="store_true",
        help="Generate one source metadata YAML file for non-GitHub distribution channels.",
    )
    parser.add_argument("--version", default=None, help="Semantic version without the leading v.")
    return parser.parse_args()


"""
Run the package build and print the generated artifact paths.
执行打包流程并输出生成的产物路径。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    out_dir = (root / args.out_dir).resolve()
    manifest = load_manifest(root)
    version = resolve_version(manifest, args.version)
    package_path, checksum_path = build_package(root, out_dir, version)
    print(f"Package created: {package_path}")
    print(f"Checksums created: {checksum_path}")
    if args.emit_source_yaml:
        source_path = build_source_metadata(
            root,
            out_dir,
            version,
            args.base_url,
            package_path,
            checksum_path,
        )
        print(f"Source metadata created: {source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
