from pathlib import Path
import os

from cybulde.utils.utils import get_logger, run_shell_command

DATA_UTILS_LOGGER = get_logger(Path(__file__).name)


def initialize_dvc() -> None:
    """
    Repo'da DVC başlat. Zaten başlatılmışsa dokunma.
    """
    if Path(".dvc").exists():
        DATA_UTILS_LOGGER.info("DVC is already initialized.")
        return

    run_shell_command("dvc init -q")
    # İlk kurulumda .dvc ve .gitignore değişir
    run_shell_command("git add .dvc .gitignore")
    try:
        run_shell_command("git commit -m 'Initialize DVC'")
    except RuntimeError:
        # commit edilecek bir şey yoksa sorun değil
        pass
    DATA_UTILS_LOGGER.info("DVC has been initialized.")


def initialize_dvc_storage(dvc_remote_name: str) -> None:
    """
    DVC remote'u hazırla. Zaten varsa dokunma.
    Eğer yoksa, DVC_REMOTE_URL env var'ından url bulup eklemeyi dener;
    o da yoksa sadece 'zaten varmış gibi' devam eder (script diğer yerde push deneyecek).
    """
    remotes = run_shell_command("dvc remote list").strip().splitlines()
    existing_names = [r.split()[0].rstrip(":") for r in remotes if r.strip()]
    if dvc_remote_name in existing_names:
        DATA_UTILS_LOGGER.info("DVC storage was already initialized...")
        return

    remote_url = os.getenv("DVC_REMOTE_URL", "").strip()
    if remote_url:
        run_shell_command(f"dvc remote add -d {dvc_remote_name} {remote_url}")
        run_shell_command("git add .dvc/config")
        try:
            run_shell_command("git commit -m 'Configure DVC remote'")
        except RuntimeError:
            pass
        DATA_UTILS_LOGGER.info(f"DVC storage configured as '{dvc_remote_name}'.")
    else:
        DATA_UTILS_LOGGER.info(
            f"DVC storage '{dvc_remote_name}' not found and no DVC_REMOTE_URL provided; skipping add."
        )


def _ensure_not_tracked_by_git(path: str) -> None:
    """
    path Git tarafından izleniyorsa index’ten çıkar (dosyaları silmeden).
    """
    try:
        run_shell_command(f'git ls-files --error-unmatch {path}')
        # Buraya düşerse demek ki izleniyor:
        run_shell_command(f'git rm -r --cached {path}')
    except RuntimeError:
        # İzlenmiyorsa sorun yok
        pass


def commit_to_dvc(dvc_raw_data_folder: str, dvc_remote_name: str) -> None:
    """
    data/raw (veya verilen klasör) için:
    - Git index'inden çıkar (takip ediliyorsa)
    - dvc add
    - değişiklik varsa commit + tag (vN) + dvc push + git push (follow-tags)
    - değişiklik yoksa bile uzak boş olabilir => yine dvc push dene
    """
    # mevcut en büyük vN etiketini bul, +1 yap
    try:
        tags = run_shell_command("git tag").strip().splitlines()
        numbers = [int(t[1:]) for t in tags if t.startswith("v") and t[1:].isdigit()]
        current = max(numbers) if numbers else 0
    except Exception:
        current = 0
    next_version = f"v{current+1}"

    # Aynı klasörü hem Git hem DVC izleyemez → önce index’ten çıkar
    _ensure_not_tracked_by_git(dvc_raw_data_folder)

    # DVC stage'i güncelle (değişiklik yoksa .dvc aynı kalabilir)
    run_shell_command(f"dvc add {dvc_raw_data_folder}")

    # Sadece ilgili dosyaları stage'e alalım
    run_shell_command(f"git add {dvc_raw_data_folder}.dvc .gitignore")

    # Değişiklik var mı?
    staged = run_shell_command("git diff --cached --name-only").strip()
    if not staged:
        # Değişiklik yok ama bucket boş olabilir → yine de push et
        run_shell_command(f"dvc push --remote {dvc_remote_name}")
        DATA_UTILS_LOGGER.info("No changes to commit; ensured remote is populated (if needed).")
        return

    # Değişiklik varsa commit + tag + push
    run_shell_command(f"git commit -m 'Updated data version -> {next_version}'")
    run_shell_command(f'git tag -a {next_version} -m "Data version {next_version}"')

    # Uzağa veri
    run_shell_command(f"dvc push --remote {dvc_remote_name}")

    # Commit + tag'leri kesinlikle it (hata olursa görünür şekilde patlasın)
    # Upstream yoksa Makefile'daki git-remote-bootstrap hedefi ayarlıyor olacak.
    run_shell_command("git push --follow-tags")


def make_new_data_version(dvc_raw_data_folder: str, dvc_remote_name: str) -> None:
    """
    .dvc dosyası yoksa ilk kez versiyonla.
    Varsa status'e bak:
      - up to date ise bile, uzak boş olabilir → dvc push yap.
      - değilse commit_to_dvc ile yeni sürüm çıkar.
    """
    dvc_file = Path(f"{dvc_raw_data_folder}.dvc")
    if not dvc_file.exists():
        commit_to_dvc(dvc_raw_data_folder, dvc_remote_name)
        return

    try:
        status = run_shell_command(f"dvc status {dvc_raw_data_folder}.dvc").strip().lower()
    except RuntimeError:
        status = ""

    if "up to date" in status:
        DATA_UTILS_LOGGER.info("Up to date locally; ensuring remote is populated...")
        run_shell_command(f"dvc push --remote {dvc_remote_name}")
        return

    # Değişiklik var → yeni sürümle
    commit_to_dvc(dvc_raw_data_folder, dvc_remote_name)
