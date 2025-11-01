from cybulde.config_schemas.config_schema import Config
from cybulde.utils.config_utils import get_config
from cybulde.utils.data_utils import commit_to_dvc, initialize_dvc, initialize_dvc_storage
from cybulde.utils.utils import get_logger


@get_config(config_path="../configs", config_name="config")
def version_data(config: Config) -> None:
    initialize_dvc()

    initialize_dvc_storage(config.dvc_remote_name, config.dvc_remote_url)

    commit_to_dvc(config.dvc_raw_data_folder, config.dvc_remote_name)


if __name__ == "__main__":
    version_data()  # type: ignore
