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

# Git kimliği/remote için env'den beslenelim (.env dosyasına koyabilirsin)
GIT_USER_NAME      ?=
GIT_USER_EMAIL     ?=
GIT_REMOTE_URL     ?=
GIT_DEFAULT_BRANCH ?= main

# ---------- Phony ----------
.PHONY: help up build down restart ps logs sh dvc-install git-bootstrap git-ssh-bootstrap git-remote-bootstrap dvc-bootstrap version-data dvc-status dvc-push dvc-pull

# ---------- Help ----------
help:
	@echo ""
	@echo "Targets:"
	@echo "  up                   - docker compose up -d"
	@echo "  build                - docker compose build --pull"
	@echo "  down                 - docker compose down"
	@echo "  restart              - down + up"
	@echo "  ps                   - docker compose ps"
	@echo "  logs                 - docker compose logs --no-color $(SERVICE)"
	@echo "  sh                   - shell içine gir (bash)"
	@echo "  dvc-install          - container içinde DVC'yi (gs desteğiyle) root olarak kur"
	@echo "  git-ssh-bootstrap    - SSH known_hosts ve izinleri hazırla (GitHub için)"
	@echo "  git-bootstrap        - repo-local git user.name/email + safe.directory"
	@echo "  git-remote-bootstrap - origin ve upstream ayarla (GIT_REMOTE_URL gerekir)"
	@echo "  dvc-bootstrap        - İlk kurulum: data/raw'ı Git index'inden çıkar + dvc add + commit (yoksa)"
	@echo "  version-data         - Tüm akış (DVC kur, git bootstrap, python scripti, garanti push)"
	@echo "  dvc-status           - dvc status data/raw.dvc"
	@echo "  dvc-push             - dvc push"
	@echo "  dvc-pull             - dvc pull"
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

# SSH (opsiyonel ama önerilir): known_hosts ve izinler
git-ssh-bootstrap: up
	$(DC) exec $(SERVICE) bash -lc '\
	  set -e; \
	  mkdir -p $$HOME/.ssh; chmod 700 $$HOME/.ssh; \
	  touch $$HOME/.ssh/known_hosts; chmod 644 $$HOME/.ssh/known_hosts; \
	  command -v ssh-keyscan >/dev/null 2>&1 && ssh-keyscan -H github.com >> $$HOME/.ssh/known_hosts 2>/dev/null || true; \
	'

# Repo-local kimlik ve safe.directory
git-bootstrap: up
	@# Kimlik env ile geldiyse repo-local ayarla; gelmediyse mevcut ayarlara dokunma
	$(DC) exec -e GIT_USER_NAME='$(GIT_USER_NAME)' -e GIT_USER_EMAIL='$(GIT_USER_EMAIL)' $(SERVICE) bash -lc '\
	  set -e; \
	  if [ -n "$$GIT_USER_EMAIL" ]; then git config --local user.email "$$GIT_USER_EMAIL"; fi; \
	  if [ -n "$$GIT_USER_NAME"  ]; then git config --local user.name  "$$GIT_USER_NAME";  fi; \
	  git config --global --add safe.directory "$$(pwd)"; \
	  echo "git user: $$(git config --local user.name 2>/dev/null || echo '-') <$$(git config --local user.email 2>/dev/null || echo '-')>"; \
	'

# origin ve upstream ayarlama (HTTPS token veya SSH URL kullan)
git-remote-bootstrap: up
	$(DC) exec -e GIT_REMOTE_URL='$(GIT_REMOTE_URL)' -e GIT_DEFAULT_BRANCH='$(GIT_DEFAULT_BRANCH)' $(SERVICE) bash -lc '\
	  set -e; \
	  if ! git remote | grep -q "^origin$$"; then \
	    test -n "$$GIT_REMOTE_URL" || (echo "ERROR: Set GIT_REMOTE_URL in .env (e.g. git@github.com:user/repo.git)"; exit 1); \
	    git remote add origin "$$GIT_REMOTE_URL"; \
	  fi; \
	  default_branch=$${GIT_DEFAULT_BRANCH:-main}; \
	  git branch -M "$$default_branch"; \
	  # upstream yoksa ilk push sırasında ayarla (varsa no-op olabilir) \
	  git push -u origin "$$default_branch" || true; \
	'

# İlk kurulum koruması:
# - data/raw Git index'inden çıkarılır (dosyalar silinmez)
# - .dvc yoksa dvc add + commit yapılır
dvc-bootstrap: up dvc-install
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
# version_data.py: initialize_dvc(), initialize_dvc_storage(), make_new_data_version()
#  -> İlk çalıştırma + sonraki güncellemeler: commit + tag + dvc push + git push (follow-tags)
version-data: git-ssh-bootstrap git-bootstrap git-remote-bootstrap dvc-bootstrap
	$(DC) exec $(SERVICE) bash -lc '\
	  set -e; \
	  python ./cybulde/version_data.py; \
	  # script zaten push ediyor; yine de ekstra güven için: \
	  git push --follow-tags || true; \
	'

# ---------- Convenience ----------
dvc-status: up
	$(DC) exec $(SERVICE) bash -lc 'dvc status data/raw.dvc || true'

dvc-push: up
	$(DC) exec $(SERVICE) bash -lc 'dvc push'

dvc-pull: up
	$(DC) exec $(SERVICE) bash -lc 'dvc pull'
