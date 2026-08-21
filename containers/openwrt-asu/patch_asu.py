from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text()
    if content.count(old) != 1:
        raise RuntimeError(f"Expected exactly one matching section in {path}")
    path.write_text(content.replace(old, new))


app_dir = Path("/app/asu")

replace_once(
    app_dir / "config.py",
    "    repository_allow_list: list = []\n",
    "    repository_allow_list: list = []\n"
    "    server_repositories: dict[str, dict[str, str]] = {}\n"
    "    server_repository_keys: dict[str, list[str]] = {}\n",
)

(app_dir / "server_repositories.py").write_text(
    '''from asu.config import settings
from asu.util import get_branch


def apply_server_repositories(build_request) -> None:
    """Add server-managed repositories to every matching build request."""
    branch = get_branch(build_request.version)["name"]
    server_repositories = {
        name: url.format(
            version=build_request.version,
            branch=branch,
            target=build_request.target,
        )
        for name, url in settings.server_repositories.get(branch, {}).items()
    }

    if server_repositories:
        build_request.repositories = {
            **build_request.repositories,
            **server_repositories,
        }
        # Preserve the official ImageBuilder feeds and append the custom ones.
        build_request.repositories_mode = "append"

    build_request.repository_keys = [
        *settings.server_repository_keys.get(branch, []),
        *build_request.repository_keys,
    ]
'''
)

api_path = app_dir / "routers" / "api.py"
replace_once(
    api_path,
    "from asu.config import settings\n",
    "from asu.config import settings\n"
    "from asu.server_repositories import apply_server_repositories\n",
)
replace_once(
    api_path,
    "    build_request.profile = build_request.profile.replace(\",\", \"_\")\n\n"
    "    add_build_event(\"requests\")\n",
    "    build_request.profile = build_request.profile.replace(\",\", \"_\")\n"
    "    apply_server_repositories(build_request)\n\n"
    "    add_build_event(\"requests\")\n",
)
