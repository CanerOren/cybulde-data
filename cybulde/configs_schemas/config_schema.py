from hydra.core.config_store import ConfigStore
from pydantic.dataclasses import dataclass

@dataclass 
class Config:
    hello: str = "world"
    dvc_remote_name: str = "gcs-storage"
    dvc_remote_url: str = "gs://cybulde_emkademy/data/raw"


def setup_config() -> None:
    cs = ConfigStore.instance()
    cs.store(name="config_schema", node=Config)