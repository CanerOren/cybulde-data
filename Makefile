# Make all targets .PHONY
.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

SHELL = /usr/bin/env bash
USER_NAME = $(shell whoami)
USER_ID = $(shell id -u)
HOST_NAME = $(shell hostname)

ifeq (, $(shell which docker-compose))
	DOCKER_COMPOSE_COMMAND = docker compose
else
	DOCKER_COMPOSE_COMMAND = docker-compose
endif

SERVICE_NAME   = app
CONTAINER_NAME = cybulde-data-container

# Compose helpers
DOCKER_COMPOSE_RUN  = $(DOCKER_COMPOSE_COMMAND) run --rm $(SERVICE_NAME)
DOCKER_COMPOSE_EXEC = $(DOCKER_COMPOSE_COMMAND) exec $(SERVICE_NAME)
DOCKER_COMPOSE_EXEC_ROOT = $(DOCKER_COMPOSE_COMMAND) exec -u 0 $(SERVICE_NAME)

# Project dirs
DIRS_TO_VALIDATE = cybulde

# --- Git/DVC config (env ile override edilebilir) ---
GIT_USER_NAME      ?=
GIT_USER_EMAIL     ?=
GIT_REMOTE_URL     ?=
GIT_DEFAULT_BRANCH ?= main

DVC_REMOTE_NAME ?= gcs-storage
DVC_RAW_DIR     ?= data/raw

export

# Returns true if the stem is a non-empty environment variable, or else raises an error.
guard-%:
	@#$(or ${$*}, $(error $* is not set))

## Version data  (ENHANCED: dvc install/bootstrap + push)
version-data: up dvc-install git-ssh-bootstrap git-bootstrap git-remote-bootstrap dvc-bootstrap
	$(DOCKER_COMPOSE_EXEC) python ./cybulde/version_data.py
	# Garantici: script zaten push ediyor ama uzak kesin dolsun:
	-$(DOCKER_COMPOSE_EXEC) dvc push --remote $(DVC_REMOTE_NAME)
	-$(DOCKER_COMPOSE_EXEC) git push --follow-tags

## Starts jupyter lab
notebook: up
	$(DOCKER_COMPOSE_EXEC) jupyter-lab --ip 0.0.0.0 --port 8888 --no-browser

## Sort code using isort
sort: up
	$(DOCKER_COMPOSE_EXEC) isort --atomic $(DIRS_TO_VALIDATE)

## Check sorting using isort
sort-check: up
	$(DOCKER_COMPOSE_EXEC) isort --check-only --atomic $(DIRS_TO_VALIDATE)

## Format code using black
format: up
	$(DOCKER_COMPOSE_EXEC) black $(DIRS_TO_VALIDATE)

## Check format using black
format-check: up
	$(DOCKER_COMPOSE_EXEC) black --check $(DIRS_TO_VALIDATE)

## Format and sort code using black and isort
format-and-sort: sort format

## Lint code using flake8
lint: up format-check sort-check
	$(DOCKER_COMPOSE_EXEC) flake8 $(DIRS_TO_VALIDATE)

## Check type annotations using mypy
check-type-annotations: up
	$(DOCKER_COMPOSE_COMMAND) exec $(SERVICE_NAME) bash -lc 'PYTHONPATH=/app MYPYPATH= poetry run mypy --install-types --non-interactive --explicit-package-bases cybulde'

## Run tests with pytest
test: up
	$(DOCKER_COMPOSE_EXEC) pytest

## Perform a full check
full-check: lint check-type-annotations
	$(DOCKER_COMPOSE_EXEC) pytesta --cov --cov-report xml --verbose

## Builds docker image
build:
	$(DOCKER_COMPOSE_COMMAND) build $(SERVICE_NAME)

## Remove poetry.lock and build docker image
build-for-dependencies:
	rm -f *.lock
	$(DOCKER_COMPOSE_COMMAND) build $(SERVICE_NAME)

## Lock dependencies with poetry
lock-dependencies: build-for-dependencies
	$(DOCKER_COMPOSE_RUN) bash -c "if [ -e /home/$(USER_NAME)/poetry.lock.build ]; then cp /home/$(USER_NAME)/poetry.lock.build ./poetry.lock; else poetry lock; fi"

## Starts docker containers using "docker-compose up -d"
up:
	$(DOCKER_COMPOSE_COMMAND) up -d

## docker-compose down
down:
	$(DOCKER_COMPOSE_COMMAND) down

## Open an interactive shell in docker container
exec-in: up
	docker exec -it $(CONTAINER_NAME) bash

# -------------------- NEW: Git & DVC utilities --------------------

## Install/ensure DVC in container (root pip fallback)
dvc-install: up
	@# varsa sürümünü göster; yoksa root pip ile kur
	$(DOCKER_COMPOSE_EXEC) sh -lc 'command -v dvc >/dev/null 2>&1 && dvc --version || exit 1' \
	|| $(DOCKER_COMPOSE_EXEC_ROOT) bash -lc 'pip install -U "dvc[gs]" && dvc --version'

## Add github.com to known_hosts (SSH push için önerilir)
git-ssh-bootstrap: up
	$(DOCKER_COMPOSE_EXEC) bash -lc '\
	  set -e; \
	  mkdir -p $$HOME/.ssh; chmod 700 $$HOME/.ssh; \
	  touch $$HOME/.ssh/known_hosts; chmod 644 $$HOME/.ssh/known_hosts; \
	  command -v ssh-keyscan >/dev/null 2>&1 && ssh-keyscan -H github.com >> $$HOME/.ssh/known_hosts 2>/dev/null || true; \
	'

## Repo-local git kimliği + safe.directory (env ile override)
git-bootstrap: up
	$(DOCKER_COMPOSE_EXEC) bash -lc '\
	  set -e; \
	  if [ -n "$(GIT_USER_EMAIL)" ]; then git config --local user.email "$(GIT_USER_EMAIL)"; fi; \
	  if [ -n "$(GIT_USER_NAME)"  ]; then git config --local user.name  "$(GIT_USER_NAME)";  fi; \
	  git config --global --add safe.directory "$$(pwd)"; \
	  echo "git user: $$(git config --local user.name 2>/dev/null || echo '-') <$$([ -n "$(GIT_USER_EMAIL)" ] && echo "$(GIT_USER_EMAIL)" || git config --local user.email 2>/dev/null || echo '-')>"; \
	'

## origin/upstream ayarla (GIT_REMOTE_URL gerekebilir)
git-remote-bootstrap: up
	$(DOCKER_COMPOSE_EXEC) bash -lc '\
	  set -e; \
	  if ! git remote | grep -q "^origin$$"; then \
	    [ -n "$(GIT_REMOTE_URL)" ] || { echo "WARN: GIT_REMOTE_URL boş; origin var sayılıyor."; exit 0; }; \
	    git remote add origin "$(GIT_REMOTE_URL)"; \
	  fi; \
	  default_branch="$(GIT_DEFAULT_BRANCH)"; \
	  git branch -M "$$default_branch"; \
	  git push -u origin "$$default_branch" || true; \
	'

## İlk kurulum: data/raw Git index’inden çıkar + .dvc yoksa ekle/commit
dvc-bootstrap: up dvc-install
	$(DOCKER_COMPOSE_EXEC) bash -lc '\
	  set -e; \
	  if git ls-files --error-unmatch $(DVC_RAW_DIR) >/dev/null 2>&1; then \
	    git rm -r --cached $(DVC_RAW_DIR); \
	  fi; \
	  if [ ! -f $(DVC_RAW_DIR).dvc ]; then \
	    dvc add $(DVC_RAW_DIR); \
	    git add $(DVC_RAW_DIR).dvc .gitignore; \
	    git commit -m "Track $(DVC_RAW_DIR) with DVC" || true; \
	  fi; \
	'

## dvc status helper
dvc-status: up
	-$(DOCKER_COMPOSE_EXEC) dvc status $(DVC_RAW_DIR).dvc

## dvc push helper
dvc-push: up
	$(DOCKER_COMPOSE_EXEC) dvc push --remote $(DVC_REMOTE_NAME)

## dvc pull helper
dvc-pull: up
	$(DOCKER_COMPOSE_EXEC) dvc pull --remote $(DVC_REMOTE_NAME)

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=36 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
