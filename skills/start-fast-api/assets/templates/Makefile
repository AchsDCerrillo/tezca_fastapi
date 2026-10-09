.PHONY: install lint format typecheck test check run migrate migration up down logs

install:          ## dev dependencies + git hooks
	pip install -r requirements-dev.txt
	pre-commit install

lint:             ## ruff lint + format check
	ruff check .
	ruff format --check .

format:           ## auto-fix lint + format
	ruff check --fix .
	ruff format .

typecheck:
	mypy

test:             ## needs Docker (testcontainers) or TEST_DATABASE_* env vars
	pytest

check: lint typecheck test

run:
	ENVIRONMENT=dev uvicorn main:app --reload

migrate:
	ENVIRONMENT=dev alembic upgrade head

migration:        ## make migration m="add products table"
	ENVIRONMENT=dev alembic revision --autogenerate -m "$(m)"

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f api
