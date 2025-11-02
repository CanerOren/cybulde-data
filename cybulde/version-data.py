from cybulde.configs_schemas.config_schema import Config
from cybulde.utils.config_utils import get_config
from cybulde.utils.data_utils import intialize_dvc
from cybulde.utils.utils import get_logger


@get_config(config_path="../configs", config_name="config")
def version_data(config: Config) -> None:

    intialize_dvc()

if __name__ == "__main__":
    version_data() # type: ignore