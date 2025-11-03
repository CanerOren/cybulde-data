# syntax=docker/dockerfile:1.7
FROM python:3.12-slim

# -- Ortak env'ler --
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # mypy / importlar için tek kök
    PYTHONPATH=/app

# -- Sistem bağımlılıkları --
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client build-essential \
    curl ca-certificates \
    graphviz \
 && rm -rf /var/lib/apt/lists/*

# -- Non-root kullanıcı (compose build arg'larıyla eşleşir) --
ARG USER_NAME=caner
ARG USER_ID=1000
RUN useradd -m -u ${USER_ID} ${USER_NAME}

WORKDIR /app

# -- Poetry ile bağımlılıklar --
ENV POETRY_VERSION=1.8.3
RUN pip install "poetry==${POETRY_VERSION}"
# Proje bağımlılıklarını sistem env'e kur (venv yok)
RUN poetry config virtualenvs.create false

# Sadece lock ve toml kopyala; bağımlılıkları çöz
COPY pyproject.toml poetry.lock* ./
RUN poetry install --no-interaction --no-ansi

# Çalışma sırasında make hedeflerinde kullanılan araçları garantiye al
# (poetry’de dev dep olarak yoksa buradan gelir; varsa zaten atlar)
RUN pip install -U mypy flake8 black isort pytest "dvc[gs]" jupyterlab

# Non-root’a geç (volume izinleri için iyi pratik)
USER ${USER_NAME}

CMD ["bash"]
