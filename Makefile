# ---------- Settings ----------
SHELL := /usr/bin/env bash

# Detect old vs new compose CLI
ifeq (, $(shell which docker-compose))
  DC := docker compose
else
  DC := docker-compose
endif

SERVICE   ?= app
CONTAINER ?= cybulde-data-container

# ---------- Phony ----------
.PHONY: help up build down restart ps logs sh dvc-install git-bootstrap dvc-bootstrap version-data dvc-status dvc-push dvc-pull

# ---------- Help ----------
help:
	@echo ""
	@echo "Targets:"
	@echo "  up               - docker compose up -d"
	@echo "  build            - docker compose build --pull"
	@echo "  down             - docker compose down"
	@echo "  restart          - down + up"
	@echo "  ps               - docker compose ps"
	@echo "  logs             - docker compose logs --no-color $(SERVICE)"
	@echo "  sh               - shell içine gir (bash)"
	@echo "  dvc-install      - container içinde DVC'yi (gs desteğiyle) root olarak kur"
	@echo "  git-bootstrap    - git kimliği ve safe.directory ayarı"
	@echo "  dvc-bootstrap    - İlk kurulum koruması: data/raw'ı Git index'inden çıkar + dvc add + commit"
	@echo "  version-data     - Tüm akış (DVC kur, bootstrap, Python scripti çalıştır)"
	@echo "  dvc-status       - dvc status data/raw.dvc"
	@echo "  dvc-push         - dvc push"
	@echo "  dvc-pull         - dvc pull"
	@echo ""

# ---------- Docker lifecycle ----------
up:
	$(DC) up -d

build:
	$(DC) build --pull

down:
	$(DC) down

restart: down up

ps:
	$(DC) ps

logs:
	$(DC) logs --no-color $(SERVICE)

sh:
	$(DC) exec -it $(SERVICE) bash

# ---------- DVC & Git bootstrap ----------
# DVC'yi root olarak kurar (izin derdi yaşamamak için)
dvc-install: up
	$(DC) exec -u 0 $(SERVICE) bash -lc 'pip install -U "dvc[gs]" && dvc --version'

# Git kimliği + safe.directory (WSL2 bind mount'larda kritik)
git-bootstrap: up
	$(DC) exec $(SERVICE) bash -lc '\
	  set -e; \
	  git config --global user.email "dev@local"; \
	  git config --global user.name  "dev"; \
	  git config --global --add safe.directory "$$(pwd)"; \
	'

# İlk kurulum koruması:
# - data/raw Git index'inden çıkarılır (dosyalar silinmez)
# - .dvc yoksa dvc add + commit yapılır
dvc-bootstrap: up git-bootstrap dvc-install
	$(DC) exec $(SERVICE) bash -lc '\
	  set -e; \
	  if git ls-files --error-unmatch data/raw >/dev/null 2>&1; then \
	    git rm -r --cached data/raw; \
	  fi; \
	  if [ ! -f data/raw.dvc ]; then \
	    dvc add data/raw; \
	    git add data/raw.dvc .gitignore; \
	    git commit -m "Track data/raw with DVC"; \
	  fi; \
	'

# ---------- Main flow ----------
# version_data.py içinde: initialize_dvc(), initialize_dvc_storage(), make_new_data_version()
#  -> İlk çalıştırma + sonraki güncellemeler: commit + tag + dvc push + git push --tags
version-data: dvc-bootstrap
	$(DC) exec $(SERVICE) bash -lc '\
	  set -e; \
	  python ./cybulde/version_data.py; \
	'

# ---------- Convenience ----------
dvc-status: up
	$(DC) exec $(SERVICE) bash -lc 'dvc status data/raw.dvc || true'

dvc-push: up
	$(DC) exec $(SERVICE) bash -lc 'dvc push'

dvc-pull: up
	$(DC) exec $(SERVICE) bash -lc 'dvc pull'
